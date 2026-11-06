#include "tegra_codec.h"
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#define MINIMP3_ONLY_MP3
#include "vendor/minimp3.h"
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_PULLDATA_API
#define STB_VORBIS_HEADER_ONLY
#include "vendor/stb_vorbis.c"

struct tm_decoder {
    int codec, error, rate, channels, eof;
    uint8_t input[TM_MAX_COMPRESSED];
    size_t filled;
    int16_t pcm[TM_MAX_PCM_FRAMES * 2u];
    size_t pcm_frames, pcm_cursor;
    mp3dec_t mp3;
    stb_vorbis *vorbis;
    uint8_t *vorbis_arena;
    stb_vorbis_alloc alloc;
};
static void advance(struct tm_decoder *d, size_t consumed) {
    if (consumed > d->filled) { d->error = TM_ERR_DECODE; return; }
    d->filled -= consumed;
    if (d->filled) memmove(d->input, d->input + consumed, d->filled);
}
static int valid_format(struct tm_decoder *d, int rate, int channels) {
    if (channels < 1 || channels > 2 || rate < 8000 || rate > 192000) {
        d->error = TM_ERR_FORMAT; return 0;
    }
    if (d->rate && (d->rate != rate || d->channels != channels)) {
        d->error = TM_ERR_FORMAT; return 0;
    }
    d->rate = rate; d->channels = channels;
    return 1;
}
static int16_t clip_float(float value) {
    if (value >= 1.f) return INT16_MAX;
    if (value <= -1.f) return INT16_MIN;
    float x = value * 32768.f;
    return (int16_t)(x >= 0.f ? x + 0.5f : x - 0.5f);
}
tm_decoder *tm_create(int codec) {
    if (codec != TM_CODEC_MP3 && codec != TM_CODEC_OGG_VORBIS) return NULL;
    struct tm_decoder *d = (struct tm_decoder *)calloc(1, sizeof(*d));
    if (!d) return NULL;
    d->codec = codec;
    if (codec == TM_CODEC_OGG_VORBIS) {
        d->vorbis_arena = (uint8_t *)malloc(TM_OGG_ARENA_BYTES);
        if (!d->vorbis_arena) { free(d); return NULL; }
        d->alloc.alloc_buffer = (char *)d->vorbis_arena;
        d->alloc.alloc_buffer_length_in_bytes = TM_OGG_ARENA_BYTES;
    } else {
        mp3dec_init(&d->mp3);
    }
    return d;
}
void tm_reset(tm_decoder *d) {
    if (!d) return;
    if (d->vorbis) { stb_vorbis_close(d->vorbis); d->vorbis = NULL; }
    d->filled = d->pcm_frames = d->pcm_cursor = 0;
    d->rate = d->channels = d->error = d->eof = 0;
    if (d->codec == TM_CODEC_MP3) mp3dec_init(&d->mp3);
}
void tm_finish(tm_decoder *d) { if (d) d->eof = 1; }
void tm_destroy(tm_decoder *d) {
    if (!d) return;
    tm_reset(d);
    free(d->vorbis_arena);
    free(d);
}
int tm_push(tm_decoder *d, const uint8_t *bytes, size_t len) {
    if (!d || (!bytes && len)) return TM_ERR_ARG;
    if (d->error) return d->error;
    if (d->eof && len) return TM_ERR_ARG;
    if (len > TM_MAX_COMPRESSED - d->filled) return TM_ERR_BACKPRESSURE;
    if (len) memcpy(d->input + d->filled, bytes, len);
    d->filled += len;
    return (int)len;
}
static int mp3_frame(struct tm_decoder *d) {
    if (d->filled < 4) return 0;
    if (!d->rate && d->filled >= 10 && !memcmp(d->input, "ID3", 3)) {
        unsigned int tag_size = 0;
        for (int i = 6; i < 10; ++i) {
            if (d->input[i] & 0x80) { d->error = TM_ERR_FORMAT; return -1; }
            tag_size = (tag_size << 7) | d->input[i];
        }
        size_t skip = 10u + tag_size + ((d->input[5] & 0x10) ? 10u : 0u);
        if (skip > TM_MAX_COMPRESSED) { d->error = TM_ERR_FORMAT; return -1; }
        if (d->filled < skip) return 0;
        advance(d, skip);
        if (d->filled < 4) return 0;
    }
    /* minimp3's sync scanner may consume all bytes and permanently lose
     * an incomplete frame. Never offer partial frames except at EOF.
     * 4096 bytes exceeds the maximum MPEG audio frame size (~2881).
     * This retains a finite decode-start cushion under streaming input. */
    if (!d->eof && d->filled < 4096u) return 0;
    mp3dec_frame_info_t info = {0};
    mp3d_sample_t decoded[MINIMP3_MAX_SAMPLES_PER_FRAME];
    int frames = mp3dec_decode_frame(&d->mp3, d->input, (int)d->filled,
                                    decoded, &info);
    if (info.frame_bytes < 0 || (size_t)info.frame_bytes > d->filled) {
        d->error = TM_ERR_DECODE; return -1;
    }
    if (!frames) {
        if (info.frame_bytes > 0) { advance(d, (size_t)info.frame_bytes); return 1; }
        if (d->filled == TM_MAX_COMPRESSED) { d->error = TM_ERR_FORMAT; return -1; }
        return 0;
    }
    if (!valid_format(d, info.hz, info.channels)) return -1;
    if ((size_t)frames > TM_MAX_PCM_FRAMES) { d->error = TM_ERR_FORMAT; return -1; }
    for (int n = 0; n < frames; ++n) {
        d->pcm[2*n] = decoded[n * info.channels];
        d->pcm[2*n+1] = decoded[n * info.channels + (info.channels == 2)];
    }
    d->pcm_frames = (size_t)frames; d->pcm_cursor = 0;
    advance(d, (size_t)info.frame_bytes);
    return -0 + 1;
}
static int vorbis_frame(struct tm_decoder *d) {
    if (!d->vorbis) {
        int consumed = 0, error = 0;
        if (!d->filled) return 0;
        d->vorbis = stb_vorbis_open_pushdata(d->input, (int)d->filled,
                                             &consumed, &error, &d->alloc);
        if (!d->vorbis) {
            if (error == VORBIS_need_more_data && d->filled < TM_MAX_COMPRESSED)
                return 0;
            d->error = TM_ERR_FORMAT; return -1;
        }
        stb_vorbis_info info = stb_vorbis_get_info(d->vorbis);
        if (!valid_format(d, (int)info.sample_rate, info.channels)) return -1;
        if (consumed < 0 || (size_t)consumed > d->filled) {
            d->error = TM_ERR_DECODE; return -1;
        }
        advance(d, (size_t)consumed);
        return 1;
    }
    if (d->filled == 0) return 0;
    int channels = 0, samples = 0;
    float **out = NULL;
    int consumed = stb_vorbis_decode_frame_pushdata(d->vorbis,
                d->input, (int)d->filled, &channels, &out, &samples);
    if (consumed < 0 || (size_t)consumed > d->filled || samples < 0 ||
        samples > (int)TM_MAX_PCM_FRAMES) {
        d->error = TM_ERR_DECODE; return -1;
    }
    if (samples) {
        if (!out || !valid_format(d, d->rate, channels)) return -1;
        for (int n = 0; n < samples; ++n) {
            d->pcm[2*n] = clip_float(out[0][n]);
            d->pcm[2*n+1] = clip_float(out[channels == 2 ? 1 : 0][n]);
        }
        d->pcm_frames = (size_t)samples; d->pcm_cursor = 0;
    }
    if (consumed) advance(d, (size_t)consumed);
    if (consumed == 0 && samples == 0) {
        if (d->filled == TM_MAX_COMPRESSED) { d->error = TM_ERR_FORMAT; return -1; }
        return 0;
    }
    return 1;
}
int tm_pull(tm_decoder *d, int16_t *out, size_t capacity_frames) {
    if (!d || !out || !capacity_frames || capacity_frames > TM_MAX_PCM_FRAMES)
        return TM_ERR_ARG;
    if (d->error) return d->error;
    for (int i=0; i<64 && d->pcm_cursor == d->pcm_frames; ++i) {
        int step = d->codec == TM_CODEC_MP3 ? mp3_frame(d) : vorbis_frame(d);
        if (step < 0) return d->error;
        if (step == 0) break;
    }
    size_t available = d->pcm_frames - d->pcm_cursor;
    size_t take = capacity_frames < available ? capacity_frames : available;
    if (!take) {
        if (d->eof && (d->filled != 0 || !d->rate)) {
            d->error = TM_ERR_FORMAT;
            return d->error;
        }
        return 0;
    }
    memcpy(out, d->pcm + 2*d->pcm_cursor, take*2*sizeof(*out));
    d->pcm_cursor += take;
    return (int)take;
}
int tm_sample_rate(const tm_decoder *d) { return d ? d->rate : 0; }
int tm_channels(const tm_decoder *d) { return d ? d->channels : 0; }
size_t tm_buffered_input(const tm_decoder *d) { return d ? d->filled : 0; }
size_t tm_buffered_output_frames(const tm_decoder *d) {
    return d ? d->pcm_frames - d->pcm_cursor : 0;
}
int tm_error(const tm_decoder *d) { return d ? d->error : TM_ERR_ARG; }
size_t tm_context_bytes(const tm_decoder *d) {
    return d ? sizeof(*d) + (d->vorbis_arena ? TM_OGG_ARENA_BYTES : 0) : 0;
}
