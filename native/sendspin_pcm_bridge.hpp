#pragma once
// PCM callback bridge for the authenticated, pinned Sendspin player.
// Only configure the SDK for signed little-endian PCM, stereo, 16-bit, 48 kHz.
// The app must account for buffered and backend latency and report actual
// played frames to the SDK; dequeuing is NOT proof that audio was played.
#include <sendspin/player_role.h>
#include <algorithm>
#include <cstdint>
#include <array>
#include <cstring>
#include <mutex>
#include <condition_variable>
#include <chrono>
#include <functional>
#include <utility>

class MethexisSendspinPcmBridge final : public sendspin::PlayerRoleListener {
public:
    enum class Boundary {START,CLEAR,END};
    explicit MethexisSendspinPcmBridge(std::function<bool()> validate_format = {}, std::function<void(Boundary,uint64_t)> boundary = {})
        : validate_format_(std::move(validate_format)), boundary_(std::move(boundary)) {}
    static bool accepts_stream_format(const sendspin::ServerPlayerStreamObject& params) {
        return params.is_complete() && params.codec == sendspin::SendspinCodecFormat::PCM &&
               params.sample_rate == 48000 && params.channels == 2 && params.bit_depth == 16;
    }
    static constexpr size_t frame_bytes = 4;
    static constexpr size_t capacity = 19200; // 100 ms at 48 kHz stereo 16-bit

    void on_stream_start() override {
        std::lock_guard<std::mutex> guard(mutex_);
        if (!failed_clear_ && !failed_format_ && (!validate_format_ || !validate_format_())) failed_format_ = true;
        clear_locked(); active_ = !failed_clear_ && !failed_format_; waiting_clear_ = false; ++generation_;
        if(active_&&boundary_)boundary_(Boundary::START,generation_);
        clear_cv_.notify_all();
        space_cv_.notify_all();
    }
    void on_stream_end() override {
        std::lock_guard<std::mutex> guard(mutex_);
        active_ = false; waiting_clear_ = false; clear_locked(); ++generation_;
        if(boundary_)boundary_(Boundary::END,generation_);
        clear_cv_.notify_all();
        space_cv_.notify_all();
    }
    // The pinned SDK patch notifies this bridge at its ordered clear boundary.
    // Consumer must also clear its backend and reject any stale generation.
    void on_stream_clear() override { clear_pending_audio(); }
    bool flushes_audio_on_stream_clear() const override { return true; }
    void clear_pending_audio() {
        std::unique_lock<std::mutex> guard(mutex_);
        if (!active_) return;
        clear_locked(); ++generation_;
        const uint64_t target = generation_;
        if(boundary_)boundary_(Boundary::CLEAR,generation_);
        waiting_clear_ = true;
        space_cv_.notify_all();
        // The SDK sync thread must not admit post-seek frames until Godot
        // has replaced its output buffer. If the consumer stalls, fail
        // closed rather than continue with unverifiable audio ordering.
        const bool acknowledged = clear_cv_.wait_for(guard, std::chrono::milliseconds(500),
            [&] { return !active_ || generation_ != target || !waiting_clear_; });
        if (!acknowledged && active_ && generation_ == target) {
            active_ = false; waiting_clear_ = false; failed_clear_ = true; clear_locked(); ++generation_;
            space_cv_.notify_all();
        }
    }
    // A missed clear acknowledgement or unsupported format is fatal for this session.
    // Only close(), after stopping the SDK worker, may release this latch.
    bool failed() const {
        std::lock_guard<std::mutex> guard(mutex_);
        return failed_clear_ || failed_format_;
    }
    bool failed_clear() const {
        std::lock_guard<std::mutex> guard(mutex_);
        return failed_clear_;
    }
    void reset_failure_after_stop() {
        std::lock_guard<std::mutex> guard(mutex_);
        if (active_) return;
        failed_clear_ = false; failed_format_ = false;
        space_cv_.notify_all();
    }
    template <typename F> bool if_current_generation(uint64_t generation, F &&callback) {
        std::lock_guard<std::mutex> guard(mutex_);
        if (!active_ || waiting_clear_ || generation_ != generation) return false;
        callback();
        return true;
    }
    bool acknowledge_generation(uint64_t generation) {
        std::lock_guard<std::mutex> guard(mutex_);
        if (!active_ || generation != generation_) return false;
        waiting_clear_ = false;
        clear_cv_.notify_all();
        return true;
    }
    // The SDK retries TRANSFER_AUDIO immediately when its sink returns zero.
    // Respect its bounded write timeout instead of spinning a CPU core while
    // this ring is full. Only the SDK background thread waits; reads, stream
    // boundaries and shutdown wake it. Never accept old-generation bytes after
    // a wake or report a partial PCM frame as accepted.
    size_t on_audio_write(uint8_t* data, size_t length, uint32_t timeout_ms) override {
        if (!data || length == 0 || length % frame_bytes != 0) return 0;
        std::unique_lock<std::mutex> guard(mutex_);
        const uint64_t generation = generation_;
        if (failed_clear_ || failed_format_) {
            // Main may still be blocked after a fatal sink failure. Pace SDK
            // retries until its next tick closes this failed session. A
            // stop/restart wakes an in-flight wait; no failed write is accepted.
            if (timeout_ms > 0) space_cv_.wait_for(guard, std::chrono::milliseconds(timeout_ms), [&] {
                return (!failed_clear_ && !failed_format_) || generation_ != generation;
            });
            return 0;
        }
        if (!active_ || waiting_clear_) return 0;
        if (size_ == capacity && timeout_ms > 0) {
            space_cv_.wait_for(guard, std::chrono::milliseconds(timeout_ms), [&] {
                return !active_ || waiting_clear_ || generation_ != generation || size_ < capacity;
            });
        }
        if (!active_ || waiting_clear_ || generation_ != generation) return 0;
        size_t amount = std::min(length, capacity - size_);
        amount -= amount % frame_bytes;
        const size_t tail = (head_ + size_) % capacity;
        const size_t first = std::min(amount, capacity - tail);
        std::memcpy(queue_.data() + tail, data, first);
        std::memcpy(queue_.data(), data + first, amount - first);
        size_ += amount;
        return amount;
    }
    // The Godot consumer drains this queue. Generation lets it discard any
    // staging buffer retained across end/start; queue is flushed at each.
    size_t read(uint8_t* out, size_t max_bytes, uint64_t* generation) {
        if (!out || !generation || max_bytes < frame_bytes) return 0;
        std::lock_guard<std::mutex> guard(mutex_);
        *generation = generation_;
        size_t amount = std::min(max_bytes - max_bytes % frame_bytes, size_);
        const size_t first = std::min(amount, capacity - head_);
        std::memcpy(out, queue_.data() + head_, first);
        std::memcpy(out + first, queue_.data(), amount - first);
        head_ = (head_ + amount) % capacity;
        size_ -= amount;
        if (amount > 0) space_cv_.notify_one();
        return amount;
    }
    struct Snapshot {
        bool active;
        uint64_t generation;
        size_t queued_bytes;
    };
    // Publish a consistent status, so a consumer never combines a previous
    // active state with the next stream generation across a clear/end race.
    Snapshot snapshot() const {
        std::lock_guard<std::mutex> guard(mutex_);
        return {active_, generation_, size_};
    }
    uint64_t generation() const {
        std::lock_guard<std::mutex> guard(mutex_); return generation_;
    }
    size_t queued_bytes() const {
        std::lock_guard<std::mutex> guard(mutex_); return size_;
    }
private:
    mutable std::mutex mutex_;
    std::condition_variable clear_cv_;
    std::condition_variable space_cv_;
    bool waiting_clear_ = false;
    bool failed_clear_ = false;
    bool failed_format_ = false;
    std::function<bool()> validate_format_;
    // Observer only; called under bridge mutex and must never call back into it.
    std::function<void(Boundary,uint64_t)> boundary_;
    void clear_locked() { head_ = 0; size_ = 0; }
    std::array<uint8_t, capacity> queue_{};
    size_t head_ = 0;
    size_t size_ = 0;
    uint64_t generation_ = 0;
    bool active_ = false;
};
