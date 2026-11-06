#include "../sendspin_startup_buffer.hpp"
#include <array>
#include <cassert>
#include <cstdio>
struct Config {size_t audio_buffer_capacity=0;uint16_t required_lead_time_ms=0,min_buffer_ms=0;};
int main(){
 Config c;ShieldStartupBufferPolicy::apply(c);
 assert(c.audio_buffer_capacity==2097152&&c.required_lead_time_ms==4000&&c.min_buffer_ms==3000);
 assert(c.audio_buffer_capacity*2/3>ShieldStartupBufferPolicy::startup_wire_bytes);
 ShieldStartupTimeline t;std::array<uint8_t,17> b{};b[0]=4;b[7]=3;b[8]=232;
 t.first_audio(b.data(),17,9);assert(!t.snapshot().active);
 // Pre-admission poisoning is retained only as an invisible candidate.
 t.start(false,9);t.first_audio(b.data(),17,9);assert(!t.snapshot().active);
 t.clear(9);t.first_audio(b.data(),17,9);assert(!t.confirmed_snapshot(1,true,true).active);
 // Genuine start replaces that candidate. First header before accepted callback.
 t.start(false,10);b[8]=233;t.first_audio(b.data(),17,10);t.accepted_start(1);
 assert(t.snapshot().active&&t.snapshot().first_server_us==1001);
 assert(!t.confirmed_snapshot(1,true,false).active); // USER drain still deferred
 assert(t.confirmed_snapshot(1,true,true).first_server_us==1001);
 assert(!t.confirmed_snapshot(2,true,true).active&&!t.confirmed_snapshot(1,false,true).active);
 auto first=t.snapshot();t.start(true,10);assert(t.snapshot().serial==first.serial&&t.snapshot().first_server_us==1001);
 // Unadmitted other-channel clear/audio cannot replace the accepted timeline.
 t.clear(9);b[8]=234;t.first_audio(b.data(),17,9);assert(t.snapshot().first_server_us==1001);
 t.observed_end(9);assert(t.snapshot().active);
 t.clear(10);t.accepted_clear(2);assert(t.snapshot().active&&t.snapshot().first_server_us==0);
 t.first_audio(nullptr,17,10);t.first_audio(b.data(),16,10);b[0]=5;t.first_audio(b.data(),17,10);b[0]=4;
 assert(t.snapshot().first_server_us==0);t.first_audio(b.data(),17,10);assert(t.snapshot().first_server_us==1002);
 t.accepted_end(3);assert(!t.snapshot().active);
 // Opposite ordering: accepted callback first, first header later, USER later.
 t.start(false,11);t.accepted_start(4);b[8]=235;t.first_audio(b.data(),17,11);
 assert(!t.confirmed_snapshot(4,true,false).active&&t.confirmed_snapshot(4,true,true).first_server_us==1003);
 t.stop();assert(!t.snapshot().active);
 puts("STARTUP_POLICY_ADMISSION_AND_CALLBACK_ORDERINGS_PASS");
}
