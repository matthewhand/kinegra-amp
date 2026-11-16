// Experimental Godot 3 bridge to the pinned Sendspin SDK. Explicitly opened;
// not registered by the app or suitable for release before device validation.
#include <gdnative_api_struct.gen.h>
#include "godot_sendspin_vault.hpp"
#include "sendspin_session.hpp"
using namespace sendspin;
static const godot_gdnative_core_api_struct *api;
static const godot_gdnative_ext_nativescript_api_struct *ns;
static void *GDCALLINGCONV create(godot_object *, void *) { return new shieldamp::SendspinSession(); }
static void GDCALLINGCONV destroy(godot_object *, void *, void *u) { delete static_cast<shieldamp::SendspinSession*>(u); }
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
    auto *s=static_cast<shieldamp::SendspinSession*>(user); auto op=static_cast<Op>(reinterpret_cast<intptr_t>(data));
    if (op==OPEN) {
        if (argc!=1 && argc!=2) return boolean(false);
        std::unique_ptr<ShieldSendspinVault> vault;
        if (argc==2) {
            if (api->godot_variant_get_type(argv[1])!=GODOT_VARIANT_TYPE_OBJECT) return boolean(false);
            vault=std::make_unique<GodotSendspinVault>(api,argv[1]);
        }
        return boolean(s->open(read_string(argv[0]),std::move(vault)));
    }
    if (op==CLOSE) { s->close(); return boolean(true); }
    if (op==TICK) return boolean(s->tick());
    if (op==CODE) return strval(s->listener.code.c_str());
    if (op==TOKEN) {
        // Explicit user action only. Treat this as a password: never log it,
        // persist it elsewhere or put it in URLs. Require durable identity.
        if (!s->client || !s->persistence || !s->persistence->healthy()) return strval("");
        auto token=s->client->pairing_token();
        return strval(token ? token->c_str() : "");
    }
    if (op==NOW) return number(SendspinClient::now_us());
    if (op==CONFIRM) return boolean(s->confirm_pairing());
    auto snap=s->audio.snapshot();
    const bool trusted=s->is_trusted();
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
        if (!trusted || argc<1 || argc>2) return boolean(false);
        auto name=read_string(argv[0]);
        if (name=="seek") {
            if (argc!=2 || api->godot_variant_get_type(argv[1])!=GODOT_VARIANT_TYPE_INT)
                return boolean(false);
            return boolean(s->command(name,api->godot_variant_as_int(argv[1])));
        }
        return boolean(argc==1 && s->command(name));
    }
    if (op==PLAYED) {
        if (argc!=3) return boolean(false);
        for (int i=0;i<3;++i) if (api->godot_variant_get_type(argv[i])!=GODOT_VARIANT_TYPE_INT) return boolean(false);
        return boolean(s->report_played(api->godot_variant_as_int(argv[0]),
            api->godot_variant_as_int(argv[1]),api->godot_variant_as_int(argv[2])));
    }
    if (op==ACK) { if (!trusted || argc!=1 || api->godot_variant_get_type(argv[0])!=GODOT_VARIANT_TYPE_INT) return boolean(false); int64_t g=api->godot_variant_as_int(argv[0]); return boolean(g>=0 && s->audio.acknowledge_generation(static_cast<uint64_t>(g))); }
    if (op==READ) {
        godot_int limit=argc==1 && api->godot_variant_get_type(argv[0])==GODOT_VARIANT_TYPE_INT ? api->godot_variant_as_int(argv[0]) : 0;
        uint8_t buf[4096]; uint64_t generation=0;
        const size_t count=s->read_pcm(buf,limit>=0 ? static_cast<size_t>(limit) : 0,generation);
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
