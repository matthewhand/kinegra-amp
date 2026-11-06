#include "sendspin_pcm_bridge.hpp"
#include <cassert>
#include <vector>
#include <thread>
#include <chrono>
#include <atomic>
int main() {
    MethexisSendspinPcmBridge b([] { return true; });
    uint8_t sample[8] = {1,2,3,4,5,6,7,8}, out[16] = {};
    uint64_t generation = 0;
    assert(b.on_audio_write(sample, 8, 0) == 0);
    assert(!b.snapshot().active && b.snapshot().generation == 0 && b.snapshot().queued_bytes == 0);
    b.on_stream_start();
    assert(b.snapshot().active && b.snapshot().generation == 1);
    assert(b.on_audio_write(nullptr, 4, 0) == 0);
    assert(b.on_audio_write(sample, 7, 0) == 0);
    assert(b.on_audio_write(sample, 8, 0) == 8);
    assert(b.read(out, 7, &generation) == 4);
    assert(out[0] == 1 && out[3] == 4 && b.queued_bytes() == 4);
    auto old_generation = generation;
    b.on_stream_end();
    assert(b.queued_bytes() == 0 && b.generation() != old_generation);
    assert(!b.snapshot().active && b.snapshot().generation != old_generation);
    assert(b.on_audio_write(sample, 4, 0) == 0);
    b.on_stream_start();
    std::vector<uint8_t> huge(b.capacity + 4, 0);
    assert(b.on_audio_write(huge.data(), huge.size(), 0) == b.capacity);
    assert(b.on_audio_write(sample, 4, 0) == 0);
    // Exercise wraparound and verify byte order across both ring segments.
    std::vector<uint8_t> drained(b.capacity-8), refill(b.capacity-8), result(b.capacity);
    for (size_t i=0;i<refill.size();++i) refill[i]=static_cast<uint8_t>(i%251);
    assert(b.read(drained.data(), drained.size(), &generation)==drained.size());
    assert(b.on_audio_write(refill.data(), refill.size(), 0)==refill.size());
    assert(b.read(result.data(), result.size(), &generation)==result.size());
    for(size_t i=0;i<8;++i) assert(result[i]==0);
    for(size_t i=0;i<refill.size();++i) assert(result[i+8]==refill[i]);
    assert(b.on_audio_write(huge.data(), huge.size(), 0)==b.capacity);
    auto before_clear = b.generation();
    std::atomic<bool> clear_done{false};
    std::thread clear([&] { b.on_stream_clear(); clear_done.store(true); });
    for (int i=0; i<1000 && b.generation()==before_clear; ++i)
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    assert(b.queued_bytes() == 0 && b.generation() != before_clear);
    assert(b.on_audio_write(sample, 8, 0) == 0);
    assert(!clear_done.load());
    bool invoked=false;
    assert(!b.if_current_generation(before_clear,[&] { invoked=true; }));
    assert(!b.if_current_generation(b.generation(),[&] { invoked=true; }));
    assert(!invoked);
    assert(!b.acknowledge_generation(before_clear));
    assert(b.acknowledge_generation(b.generation()));
    clear.join();
    assert(clear_done.load());
    assert(b.if_current_generation(b.generation(),[&] { invoked=true; }) && invoked);
    assert(b.snapshot().active && b.snapshot().generation != before_clear && b.snapshot().queued_bytes == 0);
    assert(b.on_audio_write(sample, 8, 0) == 8);
    assert(b.read(out, sizeof out, &generation) == 8);
    assert(generation == b.generation() && out[0] == 1 && out[7] == 8);
    b.on_stream_end(); b.on_stream_start();
    std::thread a([&] { for (int i=0;i<1000;++i) b.on_audio_write(sample, 8, 0); });
    std::thread c([&] { uint8_t buf[16]; uint64_t g; for (int i=0;i<1000;++i) b.read(buf, sizeof buf, &g); });
    a.join(); c.join();
    assert(b.queued_bytes() <= b.capacity && b.queued_bytes() % 4 == 0);
    b.on_stream_end(); assert(b.queued_bytes() == 0);
    // Missing acknowledgement must not admit audio after a clear.
    b.on_stream_start();
    b.on_stream_clear();
    assert(!b.snapshot().active && b.queued_bytes() == 0);
    assert(b.on_audio_write(sample, 4, 0) == 0);
}
