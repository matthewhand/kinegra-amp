#include "sendspin_pcm_bridge.hpp"
#include <cassert>
#include <chrono>
#include <future>
#include <iostream>
#include <thread>
#include <vector>
using namespace std::chrono_literals;
int main() {
    MethexisSendspinPcmBridge bridge([] { return true; });
    bridge.on_stream_start();
    std::vector<uint8_t> fill(bridge.capacity, 7);
    uint8_t sample[4]={1,2,3,4}, read[4]={};
    uint64_t generation=0;
    auto full=[&] { assert(bridge.on_audio_write(fill.data(),fill.size(),0)==bridge.capacity); };
    full();
    const auto begin=std::chrono::steady_clock::now();
    assert(bridge.on_audio_write(sample,4,20)==0);
    assert(std::chrono::steady_clock::now()-begin>=10ms);
    assert(bridge.on_audio_write(sample,4,0)==0);
    std::cout<<"BACKPRESSURE_TIMEOUT_PASS\n";

    auto waiting=std::async(std::launch::async,[&] { return bridge.on_audio_write(sample,4,500); });
    assert(waiting.wait_for(20ms)==std::future_status::timeout);
    assert(bridge.read(read,4,&generation)==4);
    assert(waiting.wait_for(200ms)==std::future_status::ready && waiting.get()==4);
    assert(bridge.queued_bytes()==bridge.capacity);
    std::cout<<"BACKPRESSURE_READ_WAKE_PASS\n";

    auto stale=std::async(std::launch::async,[&] { return bridge.on_audio_write(sample,4,500); });
    assert(stale.wait_for(20ms)==std::future_status::timeout);
    bridge.on_stream_end();
    bridge.on_stream_start();
    assert(stale.wait_for(200ms)==std::future_status::ready && stale.get()==0);
    assert(bridge.queued_bytes()==0);
    std::cout<<"BACKPRESSURE_RESTART_REJECTS_OLD_WRITE_PASS\n";

    full();
    auto cleared_write=std::async(std::launch::async,[&] { return bridge.on_audio_write(sample,4,500); });
    assert(cleared_write.wait_for(20ms)==std::future_status::timeout);
    const auto old_generation=bridge.generation();
    auto clear=std::async(std::launch::async,[&] { bridge.on_stream_clear(); });
    for(int i=0;i<200 && bridge.generation()==old_generation;++i) std::this_thread::sleep_for(1ms);
    assert(bridge.generation()!=old_generation);
    assert(cleared_write.wait_for(200ms)==std::future_status::ready && cleared_write.get()==0);
    assert(bridge.queued_bytes()==0 && bridge.acknowledge_generation(bridge.generation()));
    assert(clear.wait_for(200ms)==std::future_status::ready);
    clear.get();
    assert(bridge.on_audio_write(sample,4,20)==4);
    assert(bridge.read(read,4,&generation)==4 && read[0]==1 && read[3]==4);
    bridge.on_stream_end();
    std::cout<<"BACKPRESSURE_CLEAR_REJECTS_OLD_WRITE_PASS\n";

    bridge.on_stream_start();
    const auto clear_begin=std::chrono::steady_clock::now();
    bridge.on_stream_clear(); // no consumer acknowledgement
    assert(std::chrono::steady_clock::now()-clear_begin>=400ms);
    assert(bridge.failed_clear() && !bridge.snapshot().active && bridge.queued_bytes()==0);
    const auto failed_begin=std::chrono::steady_clock::now();
    assert(bridge.on_audio_write(sample,4,20)==0);
    assert(std::chrono::steady_clock::now()-failed_begin>=10ms);
    assert(!bridge.acknowledge_generation(bridge.generation()));
    bridge.on_stream_end();
    bridge.on_stream_start(); // a spontaneous server stream cannot release the fatal latch
    assert(bridge.failed_clear() && !bridge.snapshot().active);
    auto failed_wait=std::async(std::launch::async,[&] { return bridge.on_audio_write(sample,4,500); });
    assert(failed_wait.wait_for(20ms)==std::future_status::timeout);
    bridge.on_stream_end();
    assert(failed_wait.wait_for(200ms)==std::future_status::ready && failed_wait.get()==0);
    assert(bridge.failed_clear());
    bridge.reset_failure_after_stop(); // SDK worker has stopped; explicit new session permitted
    assert(!bridge.failed_clear());
    bridge.on_stream_start();
    assert(bridge.snapshot().active && bridge.on_audio_write(sample,4,20)==4);
    bridge.on_stream_end();
    std::cout<<"CLEAR_TIMEOUT_FATAL_LATCH_WAKE_AND_RESET_PASS\n";
}
