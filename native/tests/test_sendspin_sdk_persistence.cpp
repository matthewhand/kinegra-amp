#include "sendspin_secure_persistence.hpp"
#include <sendspin/config.h>
#include <sendspin/client.h>
#include <cassert>
#include <iostream>
struct Vault : ShieldSendspinVault {
    ShieldSendspinBlobs committed;
    bool fail_read=false;
    bool fail_write=false;
    bool partial_write=false;
    ShieldVaultRead read(ShieldSendspinBlobs &out) override {
        if (fail_read) return ShieldVaultRead::ERROR;
        out=committed;
        return out.empty() ? ShieldVaultRead::MISSING : ShieldVaultRead::OK;
    }
    bool replace(const ShieldSendspinBlobs &s) override {
        if (!s.count("keypair") || !s.count("pairing_psk")) partial_write=true;
        if (fail_write) return false;
        committed=s;
        return true;
    }
};
struct OfflineNetwork : sendspin::SendspinNetworkProvider { bool is_network_ready() override { return false; } };
int main() {
    sendspin::SendspinClient::set_log_level(sendspin::LogLevel::NONE);
    Vault vault;
    std::string first;
    std::vector<uint8_t> first_psk;
    for (int i=0;i<2;++i) {
        ShieldSendspinPersistence store(vault);
        assert(store.prepare());
        OfflineNetwork network;
        sendspin::SendspinClientConfig config;
        config.name="Synthetic SDK persistence test"; config.server_port=0;
        sendspin::SendspinClient client(std::move(config));
        client.set_persistence_provider(&store);
        client.set_network_provider(&network);
        assert(client.start() && store.ready());
        if (i==0) { first=client.client_id(); first_psk=vault.committed.at("pairing_psk"); }
        else { assert(!first.empty() && client.client_id()==first); assert(vault.committed.at("pairing_psk")==first_psk); }
        client.stop();
        assert(store.healthy());
    }
    assert(!vault.partial_write);
    assert(vault.committed.count("keypair") && vault.committed.count("pairing_psk"));
    {
        Vault failed;
        failed.fail_write=true;
        ShieldSendspinPersistence guarded(failed);
        assert(guarded.prepare());
        OfflineNetwork network;
        sendspin::SendspinClientConfig config;
        config.name="Synthetic failed-vault test"; config.server_port=0;
        sendspin::SendspinClient client(std::move(config));
        client.set_persistence_provider(&guarded);
        client.set_network_provider(&network);
        // SDK may continue after a failed persist; the integration must check
        // ready() and refuse connection even when start() returned true.
        const bool started=client.start();
        assert(!guarded.ready() && failed.committed.empty() && !failed.partial_write);
        if (started) client.stop();
    }
    auto before=vault.committed;
    vault.fail_read=true;
    ShieldSendspinPersistence failure(vault);
    assert(!failure.prepare());
    assert(vault.committed==before);
    std::cout << "SDK_PERSISTENCE_IDENTITY_RESTART_PASS\n";
}
