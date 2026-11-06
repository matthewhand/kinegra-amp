/* Deterministic adversarial input: ASan/UBSan host-bound test, synthetic only. */
#include "../tegra_codec.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static uint32_t seed = 0x5a1fa11u;
static uint32_t next_u32(void) {
    seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5;
    return seed;
}
int main(void) {
    unsigned char sample[4096];
    int16_t output[TM_MAX_PCM_FRAMES*2];
    for (int codec=TM_CODEC_MP3; codec<=TM_CODEC_OGG_VORBIS; ++codec) {
        for (int iter=0; iter<125; ++iter) {
            tm_decoder *d=tm_create(codec);
            if (!d) return 1;
            for (int chunk=0; chunk<6; ++chunk) {
                size_t n=next_u32() % sizeof(sample);
                for (size_t b=0;b<n;b++) sample[b]=(unsigned char)next_u32();
                int p=tm_push(d,sample,n);
                if (p<0 && p!=TM_ERR_BACKPRESSURE && p!=TM_ERR_FORMAT &&
                    p!=TM_ERR_DECODE) return 2;
                for (int j=0;j<12;j++) {
                    int got=tm_pull(d,output,TM_MAX_PCM_FRAMES);
                    if (got> (int)TM_MAX_PCM_FRAMES) return 3;
                    if (got<=0) break;
                }
                if (tm_buffered_input(d)>TM_MAX_COMPRESSED ||
                    tm_buffered_output_frames(d)>TM_MAX_PCM_FRAMES) return 4;
            }
            tm_reset(d);
            if (tm_error(d)||tm_buffered_input(d)) return 5;
            tm_destroy(d);
        }
    }
    puts("PASS: 250 deterministic malformed-stream decoders, 1500 bounded chunks");
    return 0;
}
