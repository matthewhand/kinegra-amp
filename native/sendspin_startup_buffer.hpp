#pragma once
#include <cstddef>
#include <cstdint>
#include <mutex>

// These are server send-ahead requests, never an output-delay or UI sleep.
struct ShieldStartupBufferPolicy {
    static constexpr uint16_t minimum_ms=3000;
    static constexpr uint16_t startup_ms=4000;
    static constexpr size_t capacity=2097152;
    static constexpr uint32_t pcm_bytes_per_second=48000*2*2;
    static constexpr uint64_t startup_wire_bytes=(uint64_t(pcm_bytes_per_second)*startup_ms+999)/1000+((startup_ms+14)/15)*13;
    static_assert(capacity*2/3>startup_wire_bytes,"SDK encoded share must cover the requested PCM lead");
    template<class Config> static void apply(Config& config){
        config.audio_buffer_capacity=capacity;
        config.required_lead_time_ms=startup_ms;
        config.min_buffer_ms=minimum_ms;
    }
};

// Observer only: never gates playback, advances clocks or stores payloads.
// The existing SDK trace supplies top-level boundary kinds and one Type4 header.
class ShieldStartupTimeline {
public:
    struct Snapshot {bool active=false;int64_t first_server_us=0;uint64_t serial=0,generation=0,connection=0;};
    // Trace runs before role admission. These are unconfirmed candidates only.
    void start(bool bridge_active=false,uint64_t connection=1){
        std::lock_guard<std::mutex> lock(mutex_);
        if(bridge_active&&confirmed_.active){return;} // in-place/gapless update
        candidate_={true,0,++serial_,0,connection};pending_=true;clear_=false;
    }
    void clear(uint64_t connection=1){
        std::lock_guard<std::mutex> lock(mutex_);
        if(confirmed_.active&&confirmed_.connection!=connection)return;
        candidate_={true,0,++serial_,0,connection};pending_=true;clear_=true;
    }
    void observed_end(uint64_t connection){
        std::lock_guard<std::mutex> lock(mutex_);
        if(pending_&&candidate_.connection==connection)pending_=false;
    }
    // Only callbacks from the SDK's admitted player role confirm a boundary.
    // They do not wait for the separately deferred main-loop USER notification.
    void accepted_start(uint64_t generation){confirm(generation,false);}
    void accepted_clear(uint64_t generation){confirm(generation,true);}
    void accepted_end(uint64_t generation){std::lock_guard<std::mutex> lock(mutex_);confirmed_={};confirmed_.generation=generation;pending_=false;}
    void stop(){std::lock_guard<std::mutex> lock(mutex_);confirmed_={};candidate_={};pending_=false;}
    void first_audio(const uint8_t* bytes,size_t length,uint64_t connection=1){
        if(!bytes||length<17||bytes[0]!=4||(length-13)%4)return;
        uint64_t stamp=0;for(size_t i=1;i<9;++i)stamp=(stamp<<8)|bytes[i];
        if(stamp==0||stamp>INT64_MAX)return;
        std::lock_guard<std::mutex> lock(mutex_);
        Snapshot* target=pending_?&candidate_:&confirmed_;
        if(target->active&&target->connection==connection&&target->first_server_us==0)target->first_server_us=static_cast<int64_t>(stamp);
    }
    Snapshot snapshot()const{std::lock_guard<std::mutex> lock(mutex_);return confirmed_;}
    Snapshot confirmed_snapshot(uint64_t generation,bool bridge_active,bool trusted)const{
        std::lock_guard<std::mutex> lock(mutex_);
        return bridge_active&&trusted&&confirmed_.generation==generation?confirmed_:Snapshot{};
    }
private:
    void confirm(uint64_t generation,bool clearing){
        std::lock_guard<std::mutex> lock(mutex_);
        confirmed_=pending_&&clear_==clearing?candidate_:Snapshot{};
        confirmed_.generation=generation;pending_=false;
    }
    mutable std::mutex mutex_;
    Snapshot candidate_,confirmed_;
    bool pending_=false,clear_=false;
    uint64_t serial_=0;
};
