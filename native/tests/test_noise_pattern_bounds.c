/* Synthetic Noise-C pattern/constructor regression. No network, keys or storage.
 * Original test code: MIT, Kinegra ShieldAmp, 2026-11-03.
 */
#include "protocol/internal.h"
#include <stdlib.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

#ifdef NOISE_COMPARE_BASELINE
int baseline_noise_pattern_expand(uint8_t *, int, const int *, size_t);
#endif

static const struct { int id; const char *name; } patterns[] = {
#define P(x) {NOISE_PATTERN_##x, #x}
    P(N), P(K), P(X), P(NN), P(NK), P(NX), P(XN), P(XK),
    P(XX), P(KN), P(KK), P(KX), P(IN), P(IK), P(IX)
#undef P
};
static unsigned checks;
static void check(int ok) { ++checks; if (!ok) { fprintf(stderr, "NOISE_BOUNDS_FAIL check=%u\n",checks); abort(); } }
static int expand_checked(int id, const int *modifiers, size_t count) {
    struct { uint8_t before[16], body[NOISE_MAX_TOKENS], after[16]; } guarded;
    memset(&guarded,0xa5,sizeof(guarded));
    int err = noise_pattern_expand(guarded.body,id,modifiers,count);
    for (size_t i=0;i<16;++i) check(guarded.before[i]==0xa5 && guarded.after[i]==0xa5);
#ifdef NOISE_COMPARE_BASELINE
    uint8_t expected[NOISE_MAX_TOKENS];
    memset(expected,0xa5,sizeof(expected));
    int baseline = baseline_noise_pattern_expand(expected,id,modifiers,count);
    check(err==baseline);
    if (err==NOISE_ERROR_NONE) {
        size_t end=2;
        while (end<NOISE_MAX_TOKENS && expected[end]!=NOISE_TOKEN_END) ++end;
        check(end<NOISE_MAX_TOKENS);
        check(memcmp(expected,guarded.body,end+1)==0);
    }
#endif
    return err;
}
int main(void) {
    const int mods[] = {NOISE_MODIFIER_FALLBACK,NOISE_MODIFIER_HFS,
        NOISE_MODIFIER_PSK0,NOISE_MODIFIER_PSK1,NOISE_MODIFIER_PSK2,
        NOISE_MODIFIER_PSK3,INT_MAX};
    for (size_t p=0;p<sizeof(patterns)/sizeof(patterns[0]);++p) {
        check(expand_checked(patterns[p].id,NULL,0)==NOISE_ERROR_NONE);
        uint8_t expanded[NOISE_MAX_TOKENS];
        memset(expanded,0,sizeof(expanded));
        check(noise_pattern_expand(expanded,patterns[p].id,NULL,0)==NOISE_ERROR_NONE);
        const uint8_t *base=noise_pattern_lookup(patterns[p].id);
        check(base!=NULL);
        size_t len=2;
        while (len<NOISE_MAX_TOKENS && base[len]!=NOISE_TOKEN_END) ++len;
        check(len<NOISE_MAX_TOKENS);
        check(memcmp(base,expanded,len+1)==0);
        for (size_t a=0;a<sizeof(mods)/sizeof(mods[0]);++a) {
            int m[3]={mods[a],0,0};
            expand_checked(patterns[p].id,m,1);
            for (size_t b=0;b<sizeof(mods)/sizeof(mods[0]);++b) {
                m[1]=mods[b]; expand_checked(patterns[p].id,m,2);
                for (size_t c=0;c<sizeof(mods)/sizeof(mods[0]);++c) {
                    m[2]=mods[c]; expand_checked(patterns[p].id,m,3);
                }
            }
        }
        char name[80];
        snprintf(name,sizeof(name),"Noise_%s_25519_ChaChaPoly_SHA256",patterns[p].name);
        for (int role=NOISE_ROLE_INITIATOR;role<=NOISE_ROLE_RESPONDER;++role) {
            NoiseHandshakeState *state=NULL;
            check(noise_handshakestate_new_by_name(&state,name,role)==NOISE_ERROR_NONE);
            check(state!=NULL);
            check(noise_handshakestate_free(state)==NOISE_ERROR_NONE);
        }
    }
    /* The application actually negotiates KKpsk2; test both public constructor
       roles and strict PSK lengths, without using any persistent identity. */
    for (int role=NOISE_ROLE_INITIATOR;role<=NOISE_ROLE_RESPONDER;++role) {
        NoiseHandshakeState *state=NULL;
        uint8_t psk[33]={0};
        check(noise_handshakestate_new_by_name(&state,"Noise_KKpsk2_25519_ChaChaPoly_SHA256",role)==NOISE_ERROR_NONE);
        check(state!=NULL);
        check(noise_handshakestate_set_pre_shared_key(state,psk,0)!=NOISE_ERROR_NONE);
        check(noise_handshakestate_set_pre_shared_key(state,psk,31)!=NOISE_ERROR_NONE);
        check(noise_handshakestate_set_pre_shared_key(state,psk,33)!=NOISE_ERROR_NONE);
        check(noise_handshakestate_set_pre_shared_key(state,psk,32)==NOISE_ERROR_NONE);
        check(noise_handshakestate_free(state)==NOISE_ERROR_NONE);
    }
    const int invalid[]={0,-1,INT_MIN,INT_MAX};
    for (size_t i=0;i<sizeof(invalid)/sizeof(invalid[0]);++i) {
        check(noise_pattern_lookup(invalid[i])==NULL);
        check(expand_checked(invalid[i],NULL,0)==NOISE_ERROR_UNKNOWN_NAME);
    }
    const char *invalid_names[]={"Noise_BOGUS_25519_ChaChaPoly_SHA256",
        "Noise_XXinvalid_25519_ChaChaPoly_SHA256","Noise_XX_25519_Unknown_SHA256"};
    for (size_t i=0;i<sizeof(invalid_names)/sizeof(invalid_names[0]);++i) {
        NoiseHandshakeState *state=NULL;
        check(noise_handshakestate_new_by_name(&state,invalid_names[i],NOISE_ROLE_RESPONDER)!=NOISE_ERROR_NONE);
        check(state==NULL);
    }
    printf("NOISE_BOUNDS_PASS checks=%u patterns=15 constructors=30 modifier_sequences=5985 paired_suite_constructors=2\n",checks);
    return 0;
}
