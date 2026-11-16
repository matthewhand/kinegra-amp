#pragma once

#include <sendspin/client.h>
#include <sendspin/player_role.h>
#include <sendspin/controller_role.h>
#include "sendspin_pcm_bridge.hpp"
#include "sendspin_secure_persistence.hpp"
#include "sendspin_startup_buffer.hpp"
#include <ArduinoJson.h>
#ifndef SENDSPIN_ENABLE_MESSAGE_TRACE
#error "Build the SDK and adapter with the existing timestamp observer hook enabled"
#endif
#include <algorithm>
#include <cstring>
#include <memory>
#include <string>
#include <utility>

namespace shieldamp {
using namespace sendspin;

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
struct SendspinSession {
    // All public methods run on one owner thread. Objects referenced by the
    // SDK outlive it. The SDK sync thread only accesses the locked PCM bridge.
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
    std::unique_ptr<ShieldSendspinVault> vault;
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
    ~SendspinSession() { close(); }
    bool open(const std::string& url, std::unique_ptr<ShieldSendspinVault> store) {
        if (client || url.size() < 10 || url.size() > 512 ||
            (url.rfind("ws://",0)!=0 && url.rfind("wss://",0)!=0) ||
            url.find_first_of("@#\r\n\t ") != std::string::npos) return false;
        if (store) {
            vault = std::move(store);
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

    bool tick() {
        if (!client) return false;
        if (audio.failed()) { close(); return false; }
        client->loop();
        if (audio.failed() || (persistence && !persistence->healthy())) {
            close();
            return false;
        }
        return true;
    }

    bool is_trusted() {
        if (!client || !client->is_connected()) listener.trusted = false;
        return listener.trusted;
    }

    bool command(const std::string& name, int64_t position=-1) {
        if (!is_trusted() || !controller) return false;
        ClientCommandControllerObject cmd{};
        if (name=="play" && position==-1) cmd.command=SendspinControllerCommand::PLAY;
        else if (name=="pause" && position==-1) cmd.command=SendspinControllerCommand::PAUSE;
        else if (name=="stop" && position==-1) cmd.command=SendspinControllerCommand::STOP;
        else if (name=="next" && position==-1) cmd.command=SendspinControllerCommand::NEXT;
        else if (name=="previous" && position==-1) cmd.command=SendspinControllerCommand::PREVIOUS;
        else if (name=="seek") {
            const auto &state=controller->get_controller_state();
            if (position<0 || !state.seek_max_ms || static_cast<uint64_t>(position)>*state.seek_max_ms) return false;
            cmd.command=SendspinControllerCommand::SEEK;
            cmd.position_ms=static_cast<uint32_t>(position);
        } else return false;
        return controller->send_command(cmd);
    }

    bool supports(SendspinControllerCommand command) const {
        if (!listener.trusted || !controller) return false;
        const auto &commands=controller->get_controller_state().supported_commands;
        return std::find(commands.begin(),commands.end(),command)!=commands.end();
    }

    bool confirm_pairing() {
        if (!client || !listener.pairing_window) return false;
        client->confirm_pairing_window();
        return true;
    }

    size_t read_pcm(uint8_t* buffer, size_t limit, uint64_t& generation,
                    const uint64_t* expected_generation = nullptr) {
        const auto snapshot = audio.snapshot();
        generation = snapshot.generation;
        if (!is_trusted() || !buffer || limit < 4 || limit > 4096) return 0;
        if (read_generation != generation) {
            read_generation = generation;
            outstanding_frames = 0;
            last_finish = 0;
        }
        constexpr size_t max_outstanding_frames = 96000;
        const size_t available = max_outstanding_frames - outstanding_frames;
        const size_t count = audio.read(buffer, std::min(limit, available * 4), &generation, expected_generation);
        if (read_generation != generation) {
            read_generation = generation;
            outstanding_frames = 0;
            last_finish = 0;
        }
        outstanding_frames += count / 4;
        return count;
    }

    bool report_played(int64_t generation, int64_t frames, int64_t finish) {
        // The sink reports hardware-consumed frames in the SDK clock domain.
        // Reading a packet into staging cannot advance the playback cursor.
        auto snapshot = audio.snapshot();
        const int64_t now = SendspinClient::now_us();
        if (!is_trusted() || !player || !snapshot.active ||
            generation < 0 || static_cast<uint64_t>(generation) != snapshot.generation ||
            read_generation != snapshot.generation || frames <= 0 ||
            static_cast<uint64_t>(frames) > outstanding_frames ||
            finish < now - 250000 || finish > now + 2000000 || finish < last_finish)
            return false;
        if (!audio.if_current_generation(snapshot.generation, [&] {
                player->notify_audio_played(static_cast<uint32_t>(frames), finish);
            }))
            return false;
        outstanding_frames -= static_cast<size_t>(frames);
        last_finish = finish;
        return true;
    }
};
}
