#include "sendspin_pcm_bridge.hpp"
#include <cassert>
#include <iostream>
int main() {
    using namespace sendspin;
    ServerPlayerStreamObject params;
    auto valid=[&] { return MethexisSendspinPcmBridge::accepts_stream_format(params); };
    assert(!valid());
    params.codec=SendspinCodecFormat::PCM;params.sample_rate=48000;params.channels=2;params.bit_depth=16;
    assert(valid());
    for (auto rate : {0u,44100u,96000u}) { params.sample_rate=rate;assert(!valid()); }
    params.sample_rate=48000;
    for (uint8_t channels : {uint8_t(1),uint8_t(6)}) { params.channels=channels;assert(!valid()); }
    params.channels=2;
    for (uint8_t depth : {uint8_t(8),uint8_t(24),uint8_t(32)}) { params.bit_depth=depth;assert(!valid()); }
    params.bit_depth=16;params.codec=SendspinCodecFormat::FLAC;assert(!valid());
    params.codec=SendspinCodecFormat::PCM;
    MethexisSendspinPcmBridge bridge(valid);
    bridge.on_stream_start();assert(bridge.snapshot().active);
    bridge.on_stream_end();params.sample_rate=44100;
    bridge.on_stream_start();assert(!bridge.snapshot().active && bridge.failed());
    uint8_t sample[4]={};assert(bridge.on_audio_write(sample,4,0)==0);
    assert(!bridge.acknowledge_generation(bridge.generation()));
    params.sample_rate=48000;bridge.on_stream_start();assert(!bridge.snapshot().active && bridge.failed());
    bridge.on_stream_end();bridge.reset_failure_after_stop();bridge.on_stream_start();
    assert(bridge.snapshot().active && !bridge.failed());
    MethexisSendspinPcmBridge unconfigured;unconfigured.on_stream_start();assert(unconfigured.failed());
    std::cout<<"STRICT_STREAM_FORMAT_FAIL_CLOSED_PASS\n";
}
