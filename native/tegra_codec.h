#ifndef TEGRA_CODEC_H
#define TEGRA_CODEC_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

#define TM_CODEC_MP3 1
#define TM_CODEC_OGG_VORBIS 2
#define TM_MAX_COMPRESSED (128u * 1024u)
#define TM_MAX_PCM_FRAMES 8192u
#define TM_OGG_ARENA_BYTES (2u * 1024u * 1024u)
#define TM_ERR_ARG (-1)
#define TM_ERR_BACKPRESSURE (-2)
#define TM_ERR_DECODE (-3)
#define TM_ERR_FORMAT (-4)

typedef struct tm_decoder tm_decoder;
/* All methods are synchronous and NOT thread-safe. One owner per instance.
 * No file/network I/O. Push finite compressed bytes; pull stereo interleaved
 * native-rate PCM16 frames. Caller owns HTTP/queue/bus/FFT integration. */
tm_decoder *tm_create(int codec);
void tm_destroy(tm_decoder *);
void tm_reset(tm_decoder *);
void tm_finish(tm_decoder *); /* upstream EOF permits bounded decoder tail drain */
int tm_push(tm_decoder *, const uint8_t *data, size_t size);
int tm_pull(tm_decoder *, int16_t *out_interleaved, size_t capacity_frames);
int tm_sample_rate(const tm_decoder *);
int tm_channels(const tm_decoder *); /* source 1 or 2; output always stereo */
size_t tm_buffered_input(const tm_decoder *);
size_t tm_buffered_output_frames(const tm_decoder *);
int tm_error(const tm_decoder *);
size_t tm_context_bytes(const tm_decoder *); /* upper-bound allocated context */
#ifdef __cplusplus
}
#endif
#endif
