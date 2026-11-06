/* Synthetic host model of Android FORTIFY's memchr object-bound check.
 * Compile with -O3 so the compiler propagates static pattern object sizes.
 * Original test code: MIT, Kinegra ShieldAmp, 2026-11-03.
 */
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static inline void *checked_memchr(const void *p, int c, size_t n, size_t size) {
    if (size!=(size_t)-1 && n>size) {
        fprintf(stderr,"NOISE_SCAN_OVERRUN requested=%zu available=%zu\n",n,size);
        abort();
    }
    return __builtin_memchr(p,c,n);
}
#define memchr(p,c,n) checked_memchr(p,c,n,__builtin_object_size(p,0))
#include NOISE_PATTERN_SOURCE
