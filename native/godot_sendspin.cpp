// Experimental Godot 3 bridge to the pinned Sendspin SDK. Explicitly opened;
// not registered by the app or suitable for release before device validation.
#include <gdnative_api_struct.gen.h>
#include <sendspin/client.h>
#include <sendspin/player_role.h>
#include <sendspin/controller_role.h>
#include "sendspin_pcm_bridge.hpp"
#include "godot_sendspin_vault.hpp"
#include "sendspin_startup_buffer.hpp"
#include <ArduinoJson.h>
#ifndef SENDSPIN_ENABLE_MESSAGE_TRACE
#error "Build the SDK and adapter with the existing timestamp observer hook enabled"
#endif
#include <memory>
#include <algorithm>
#include <string>
#include <vector>
#include <cstring>
using namespace sendspin;
static const godot_gdnative_core_api_struct *api;
static const godot_gdnative_ext_nativescript_api_struct *ns;
struct Network final : SendspinNetworkProvider { bool is_network_ready() override { return true; } };
struct Listener final : SendspinClientListener {
    bool trusted = false;
    bool pairing_window = false;
    std::string code;
    void on_trust_changed(ConnectionTrust trust) override { trusted = trust == ConnectionTrust::USER; }
    void on_display_pairing_code(const std::string& value, SendspinPairingCodeFormat) override { code = value; }
    void on_clear_pairing_code() override { code.clear(); }
    void on_open_pairing_window() override { pairing_window = true; }
    void on_close_pairing_window() override { pairing_window = false; }
};
struct Session {
    // Objects referenced by client outlive it. No durable pairing store yet.
    Network network;
    ShieldStartupTimeline startup;
    Listener listener;
    MethexisSendspinPcmBridge audio{[this] {
        return player && MethexisSendspinPcmBridge::accepts_stream_format(player->get_current_stream_params());
    },[this](MethexisSendspinPcmBridge::Boundary kind,uint64_t generation){
        if(kind==MethexisSendspinPcmBridge::Boundary::START)startup.accepted_start(generation);
        else if(kind==MethexisSendspinPcmBridge::Boundary::CLEAR)startup.accepted_clear(generation);
        else startup.accepted_end(generation);
    }};
    std::unique_ptr<GodotSendspinVault> vault;
    std::unique_ptr<ShieldSendspinPersistence> persistence;
    std::unique_ptr<SendspinClient> client;
    ControllerRole *controller = nullptr;
    PlayerRole *player = nullptr;
    uint64_t read_generation = 0;
    size_t outstanding_frames = 0;
    int64_t last_finish = 0;
    void close() {
        audio.on_stream_end(); // releases a pending sync-thread clear wait
        if (client) { client->stop(); client.reset(); }
        audio.reset_failure_after_stop();
        controller = nullptr; player = nullptr; outstanding_frames = 0; read_generation = 0; last_finish = 0;
        persistence.reset(); vault.reset();
        listener.trusted = false; listener.code.clear(); listener.pairing_window = false;
        startup.stop();
    }
    ~Session() { close(); }
    bool open(const std::string& url, const godot_variant *store) {
        if (client || url.size() < 10 || url.size() > 512 ||
            (url.rfind("ws://",0)!=0 && url.rfind("wss://",0)!=0) ||
            url.find_first_of("@#\r\n\t ") != std::string::npos) return false;
        if (store) {
            if (api->godot_variant_get_type(store)!=GODOT_VARIANT_TYPE_OBJECT) return false;
            vault=std::make_unique<GodotSendspinVault>(api,store);
            persistence=std::make_unique<ShieldSendspinPersistence>(*vault);
            if (!persistence->prepare()) { persistence.reset(); vault.reset(); return false; }
        }
        SendspinClient::set_log_level(LogLevel::NONE); // SDK info logs include pairing secrets.
        SendspinClientConfig config;
        config.name = "Kinegra Amp"; config.product_name = "Kinegra Amp";
        config.manufacturer = "Kinegra"; config.software_version = "1.0.10";
        // Observe only inbound control kind/roles and the first audio timestamp.
        // No JSON value, audio payload, pairing material or trace is retained/logged.
        config.message_trace=[this](const SendspinTracedMessage& message){
            if(message.direction!=SendspinTraceDirection::INBOUND||!message.binary||!message.plaintext)return;
            const auto* bytes=message.plaintext;const size_t size=message.plaintext_len;
            if(size>=17&&bytes[0]==4){startup.first_audio(bytes,size,message.connection_id);return;}
            if(size<3||size>4096||bytes[0]!=0)return;
            JsonDocument filter;filter["type"]=true;filter["payload"]["roles"]=true;filter["payload"]["player"]["codec"]=true;
            JsonDocument control;
            if(deserializeJson(control,bytes+1,size-1,DeserializationOption::Filter(filter),DeserializationOption::NestingLimit(8)))return;
            const char* kind=control["type"]|"";
            bool player=true;
            if(control["payload"]["roles"].is<JsonArray>()){
                player=false;for(JsonVariant role:control["payload"]["roles"].as<JsonArray>())if(role.is<const char*>()&&std::strcmp(role.as<const char*>(),"player")==0)player=true;
            }
            if(!player)return;
            if(std::strcmp(kind,"stream/start")==0){if(control["payload"]["player"]["codec"].is<const char*>())startup.start(audio.snapshot().active,message.connection_id);}
            else if(std::strcmp(kind,"stream/clear")==0)startup.clear(message.connection_id);
            else if(std::strcmp(kind,"stream/end")==0)startup.observed_end(message.connection_id);
        };
        config.server_port = 0; // patched SDK interprets zero as outbound-only
        config.pairing_code_out_channels = {SendspinPairingCodeChannel::DISPLAY};
        config.pairing_code_formats = {SendspinPairingCodeFormat::DIGITS};
        client = std::make_unique<SendspinClient>(std::move(config));
        client->set_listener(&listener); client->set_network_provider(&network);
        if (persistence) client->set_persistence_provider(persistence.get());
        client->set_unpaired_access_enabled(false);
        PlayerRoleConfig config_player;
        config_player.audio_formats = {{SendspinCodecFormat::PCM,2,48000,16}};
        ShieldStartupBufferPolicy::apply(config_player);
        controller = &client->add_controller();
        player = &client->add_player(std::move(config_player));
        player->set_listener(&audio);
        // Until volume/mute are actually applied, do not advertise them.
        player->set_volume_adjustable(false);
        player->set_mute_adjustable(false);
        player->set_output_delay_adjustable(false);
        if (!client->start() || (persistence && !persistence->ready())) { close(); return false; }
        client->connect_to(url);
        return true;
    }
};
static void *GDCALLINGCONV create(godot_object *, void *) { return new Session(); }
static void GDCALLINGCONV destroy(godot_object *, void *, void *u) { delete static_cast<Session*>(u); }
static godot_variant boolean(bool b) { godot_variant v; api->godot_variant_new_bool(&v,b); return v; }
static godot_variant number(int64_t n) { godot_variant v; api->godot_variant_new_int(&v,n); return v; }
static godot_variant strval(const char *s) { godot_string str; api->godot_string_new(&str); api->godot_string_parse_utf8(&str,s); godot_variant v; api->godot_variant_new_string(&v,&str); api->godot_string_destroy(&str); return v; }
static std::string read_string(godot_variant *v) {
    if (api->godot_variant_get_type(v) != GODOT_VARIANT_TYPE_STRING) return {};
    godot_string s=api->godot_variant_as_string(v); godot_char_string c=api->godot_string_utf8(&s);
    std::string result(api->godot_char_string_get_data(&c),api->godot_char_string_length(&c));
    api->godot_char_string_destroy(&c); api->godot_string_destroy(&s); return result;
}
static void put(godot_dictionary *d,const char *key,godot_variant value) {
    godot_variant k=strval(key); api->godot_dictionary_set(d,&k,&value);
    api->godot_variant_destroy(&k); api->godot_variant_destroy(&value);
}
static godot_variant dictval(godot_dictionary *d) {
    godot_variant v; api->godot_variant_new_dictionary(&v,d); api->godot_dictionary_destroy(d); return v;
}
static godot_variant bytesval(const uint8_t *bytes,size_t count) {
    godot_pool_byte_array a; api->godot_pool_byte_array_new(&a);
    api->godot_pool_byte_array_resize(&a,static_cast<godot_int>(count));
    if (count) { auto *w=api->godot_pool_byte_array_write(&a); std::memcpy(api->godot_pool_byte_array_write_access_ptr(w),bytes,count); api->godot_pool_byte_array_write_access_destroy(w); }
    godot_variant v; api->godot_variant_new_pool_byte_array(&v,&a); api->godot_pool_byte_array_destroy(&a); return v;
}
enum Op { OPEN, TICK, CLOSE, STATUS, READ, ACK, CODE, CONFIRM, COMMAND, NOW, PLAYED, TOKEN };
static godot_variant GDCALLINGCONV method(godot_object *,void *data,void *user,int argc,godot_variant **argv) {
    auto *s=static_cast<Session*>(user); auto op=static_cast<Op>(reinterpret_cast<intptr_t>(data));
    if (op==OPEN) return boolean((argc==1 || argc==2) && s->open(read_string(argv[0]),argc==2 ? argv[1] : nullptr));
    if (op==CLOSE) { s->close(); return boolean(true); }
    if (op==TICK) {
        if (!s->client) return boolean(false);
        if (s->audio.failed()) { s->close(); return boolean(false); }
        s->client->loop();
        if (s->audio.failed() || (s->persistence && !s->persistence->healthy())) {
            s->close();
            return boolean(false);
        }
        return boolean(true);
    }
    if (op==CODE) return strval(s->listener.code.c_str());
    if (op==TOKEN) {
        // Explicit user action only. Treat this as a password: never log it,
        // persist it elsewhere or put it in URLs. Require durable identity.
        if (!s->client || !s->persistence || !s->persistence->healthy()) return strval("");
        auto token=s->client->pairing_token();
        return strval(token ? token->c_str() : "");
    }
    if (op==NOW) return number(SendspinClient::now_us());
    if (op==CONFIRM) { if (!s->client || !s->listener.pairing_window) return boolean(false); s->client->confirm_pairing_window(); return boolean(true); }
    auto snap=s->audio.snapshot();
    const bool connected=s->client && s->client->is_connected();
    if (!connected) s->listener.trusted = false;
    bool trusted=connected && s->listener.trusted;
    if (op==STATUS) {
        godot_dictionary d; api->godot_dictionary_new(&d);
        put(&d,"active",boolean(trusted && snap.active)); put(&d,"generation",number(snap.generation));
        put(&d,"connected",boolean(s->client && s->client->is_connected())); put(&d,"paired",boolean(trusted));
        put(&d,"pairing_window",boolean(s->listener.pairing_window)); put(&d,"client_id",strval(s->client ? s->client->client_id().c_str() : ""));
        put(&d,"persistent",boolean(s->persistence != nullptr));
        put(&d,"queued_bytes",number(trusted&&snap.active?snap.queued_bytes:0));
        auto startup=s->startup.confirmed_snapshot(snap.generation,snap.active,trusted);
        const auto now=SendspinClient::now_us();
        const auto first=startup.first_server_us>0&&s->client?s->client->get_client_time(startup.first_server_us):0;
        const bool preparing=trusted&&snap.active&&startup.active&&startup.generation==snap.generation&&(first==0||first>now);
        put(&d,"startup_buffering",boolean(preparing));
        put(&d,"startup_remaining_ms",number(preparing&&first>now?std::min<int64_t>(30000,(first-now+999)/1000):0));
        put(&d,"buffer_minimum_ms",number(ShieldStartupBufferPolicy::minimum_ms));
        put(&d,"startup_lead_ms",number(ShieldStartupBufferPolicy::startup_ms));
        auto can=[&](SendspinControllerCommand command) {
            if (!trusted || !s->controller) return false;
            const auto &commands=s->controller->get_controller_state().supported_commands;
            return std::find(commands.begin(),commands.end(),command)!=commands.end();
        };
        put(&d,"can_play",boolean(can(SendspinControllerCommand::PLAY)));
        put(&d,"can_pause",boolean(can(SendspinControllerCommand::PAUSE)));
        put(&d,"can_stop",boolean(can(SendspinControllerCommand::STOP)));
        put(&d,"can_next",boolean(can(SendspinControllerCommand::NEXT)));
        put(&d,"can_previous",boolean(can(SendspinControllerCommand::PREVIOUS)));
        return dictval(&d);
    }
    if (op==COMMAND) {
        if (!trusted || !s->controller || argc<1 || argc>2) return boolean(false);
        auto name=read_string(argv[0]);
        ClientCommandControllerObject cmd{};
        if (name=="play" && argc==1) cmd.command=SendspinControllerCommand::PLAY;
        else if (name=="pause" && argc==1) cmd.command=SendspinControllerCommand::PAUSE;
        else if (name=="stop" && argc==1) cmd.command=SendspinControllerCommand::STOP;
        else if (name=="next" && argc==1) cmd.command=SendspinControllerCommand::NEXT;
        else if (name=="previous" && argc==1) cmd.command=SendspinControllerCommand::PREVIOUS;
        else if (name=="seek" && argc==2 && api->godot_variant_get_type(argv[1])==GODOT_VARIANT_TYPE_INT) {
            godot_int position=api->godot_variant_as_int(argv[1]);
            const auto &state=s->controller->get_controller_state();
            if (position<0 || !state.seek_max_ms || static_cast<uint64_t>(position)>*state.seek_max_ms) return boolean(false);
            cmd.command=SendspinControllerCommand::SEEK;
            cmd.position_ms=static_cast<uint32_t>(position);
        } else return boolean(false);
        // The SDK independently checks current advertised commands and role
        // generation. True means queued, not acknowledged or applied.
        return boolean(s->controller->send_command(cmd));
    }
    if (op==PLAYED) {
        // The output must provide real consumed-frame counts and a finish
        // timestamp in SendspinClient::now_us() clock domain. Merely draining
        // the staging queue is NOT evidence that sound reached the DAC.
        if (!trusted || !s->player || !snap.active || argc!=3) return boolean(false);
        for (int i=0;i<3;++i) if (api->godot_variant_get_type(argv[i])!=GODOT_VARIANT_TYPE_INT) return boolean(false);
        const int64_t generation=api->godot_variant_as_int(argv[0]);
        const int64_t frames=api->godot_variant_as_int(argv[1]);
        const int64_t finish=api->godot_variant_as_int(argv[2]);
        const int64_t now=SendspinClient::now_us();
        if (generation<0 || static_cast<uint64_t>(generation)!=snap.generation || s->read_generation!=snap.generation || frames<=0 || static_cast<uint64_t>(frames)>s->outstanding_frames || finish<now-250000 || finish>now+2000000 || finish<s->last_finish) return boolean(false);
        if (!s->audio.if_current_generation(snap.generation, [&] { s->player->notify_audio_played(static_cast<uint32_t>(frames),finish); })) return boolean(false);
        s->outstanding_frames-=static_cast<size_t>(frames); s->last_finish=finish;
        return boolean(true);
    }
    if (op==ACK) { if (!trusted || argc!=1 || api->godot_variant_get_type(argv[0])!=GODOT_VARIANT_TYPE_INT) return boolean(false); int64_t g=api->godot_variant_as_int(argv[0]); return boolean(g>=0 && s->audio.acknowledge_generation(static_cast<uint64_t>(g))); }
    if (op==READ) {
        godot_int limit=argc==1 && api->godot_variant_get_type(argv[0])==GODOT_VARIANT_TYPE_INT ? api->godot_variant_as_int(argv[0]) : 0;
        uint8_t buf[4096]; uint64_t generation=snap.generation; size_t count=0;
        if (trusted && limit>=4 && limit<=4096) {
            if (s->read_generation!=snap.generation) { s->read_generation=snap.generation; s->outstanding_frames=0; s->last_finish=0; }
            constexpr size_t max_outstanding_frames=96000;
            const size_t available=max_outstanding_frames-s->outstanding_frames;
            count=s->audio.read(buf,std::min(static_cast<size_t>(limit),available*4),&generation);
            if (s->read_generation!=generation) { s->read_generation=generation; s->outstanding_frames=0; s->last_finish=0; }
            s->outstanding_frames+=count/4;
        }
        godot_dictionary d; api->godot_dictionary_new(&d); put(&d,"generation",number(generation)); put(&d,"bytes",bytesval(buf,count)); return dictval(&d);
    }
    return boolean(false);
}
extern "C" GDN_EXPORT void GDCALLINGCONV godot_gdnative_init(godot_gdnative_init_options *options) { api=options->api_struct; for (unsigned i=0;i<api->num_extensions;++i) if (api->extensions[i]->type==GDNATIVE_EXT_NATIVESCRIPT) ns=reinterpret_cast<const godot_gdnative_ext_nativescript_api_struct*>(api->extensions[i]); }
extern "C" GDN_EXPORT void GDCALLINGCONV godot_gdnative_terminate(godot_gdnative_terminate_options *) { api=nullptr; ns=nullptr; }
extern "C" GDN_EXPORT void GDCALLINGCONV godot_nativescript_init(void *handle) {
    if (!api || !ns) return;
    godot_instance_create_func constructor={create,nullptr,nullptr}; godot_instance_destroy_func destructor={destroy,nullptr,nullptr};
    ns->godot_nativescript_register_class(handle,"ShieldSendspin","Reference",constructor,destructor);
    const char *names[]={"open","tick","close","status","read","acknowledge_generation","pairing_code","confirm_pairing","command","clock_now_us","report_output_played","reveal_pairing_token"};
    godot_method_attributes attrs={GODOT_METHOD_RPC_MODE_DISABLED};
    for (intptr_t i=0;i<12;++i) { godot_instance_method m={method,reinterpret_cast<void*>(i),nullptr}; ns->godot_nativescript_register_method(handle,"ShieldSendspin",names[i],attrs,m); }
}
