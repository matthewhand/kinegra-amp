#pragma once
// Source-stage persistence adapter. A platform vault must encrypt and replace
// the complete snapshot durably and atomically. No plaintext disk fallback.
#include <sendspin/client.h>
#include <sendspin/persistence_keys.h>
#include <algorithm>
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <vector>

using ShieldSendspinBlobs = std::map<std::string,std::vector<uint8_t>>;
enum class ShieldVaultRead { OK, MISSING, ERROR };
class ShieldSendspinVault {
public:
    virtual ~ShieldSendspinVault() = default;
    // ERROR includes authentication, corruption, unsupported format, and IO.
    virtual ShieldVaultRead read(ShieldSendspinBlobs &out) = 0;
    // On false the previous committed snapshot must remain intact.
    virtual bool replace(const ShieldSendspinBlobs &snapshot) = 0;
};
class ShieldSendspinPersistence final : public sendspin::SendspinPersistenceProvider {
public:
    explicit ShieldSendspinPersistence(ShieldSendspinVault &vault) : vault_(vault) {}
    // Must be called before assigning to the SDK. A storage error cannot be
    // represented by SDK load_blob's nullopt, so never start after a failure.
    bool prepare() {
        ShieldSendspinBlobs loaded;
        const auto result=vault_.read(loaded);
        if (result==ShieldVaultRead::ERROR || (result==ShieldVaultRead::MISSING && !loaded.empty())) return fail();
        if (loaded.size()>17) return fail();
        for (const auto &entry:loaded) if (!valid(entry.first,entry.second.size())) return fail();
        if (result==ShieldVaultRead::OK) {
            // The SDK normally regenerates missing or invalid identity data.
            // Existing encrypted snapshots must fail closed instead.
            auto id=loaded.find(sendspin::persistence_keys::KEYPAIR);
            auto psk=loaded.find(sendspin::persistence_keys::PAIRING_PSK);
            if (id==loaded.end() || psk==loaded.end() || all_zero(id->second) || all_zero(psk->second)) return fail();
        }
        bootstrap_=(result==ShieldVaultRead::MISSING);
        blobs_=std::move(loaded); prepared_=true; failed_=false; return true;
    }
    std::optional<std::vector<uint8_t>> load_blob(const std::string &key) override {
        if (!prepared_ || failed_ || !known(key)) { failed_=true; return std::nullopt; }
        auto entry=blobs_.find(key);
        return entry==blobs_.end() ? std::nullopt : std::optional<std::vector<uint8_t>>(entry->second);
    }
    bool save_blob(const std::string &key,const uint8_t *data,size_t length) override {
        if (!prepared_ || failed_ || !data || !valid(key,length)) return fail();
        std::vector<uint8_t> value(data,data+length);
        auto prior=blobs_.find(key);
        if ((key==sendspin::persistence_keys::KEYPAIR || key==sendspin::persistence_keys::PAIRING_PSK) &&
            (all_zero(value) || (prior!=blobs_.end() && prior->second!=value))) return fail();
        auto next=blobs_;
        next[key]=std::move(value);
        if (bootstrap_) {
            // The pinned SDK provisions the PSK and identity separately.
            // Persist neither alone if the process stops mid-bootstrap.
            if (!next.count(sendspin::persistence_keys::KEYPAIR) || !next.count(sendspin::persistence_keys::PAIRING_PSK)) {
                blobs_=std::move(next);
                return true;
            }
            if (!vault_.replace(next)) return fail();
            blobs_=std::move(next);
            bootstrap_=false;
            return true;
        }
        // SDK may omit commit for advisory values, so every later save is durable.
        if (!vault_.replace(next)) return fail();
        blobs_=std::move(next);
        return true;
    }
    bool commit() override { return prepared_ && !failed_ && !bootstrap_; }
    bool healthy() const { return prepared_ && !failed_; }
    bool ready() const { return healthy() && !bootstrap_; }
private:
    static bool all_zero(const std::vector<uint8_t> &value) { return std::all_of(value.begin(),value.end(),[](uint8_t x){ return x==0; }); }
    static bool known(const std::string &key) {
        using namespace sendspin::persistence_keys;
        if (key==KEYPAIR || key==PAIRING_PSK || key==RECORD_ORDER || key==LAST_PLAYED || key==OUTPUT_DELAY) return true;
        for (size_t i=0;i<12;++i) if (key==record_slot_key(i)) return true;
        return false;
    }
    static bool valid(const std::string &key,size_t length) {
        using namespace sendspin::persistence_keys;
        if (key==KEYPAIR || key==PAIRING_PSK || key==LAST_PLAYED) return length==32;
        if (key==OUTPUT_DELAY) return length==2;
        if (key==RECORD_ORDER) return length==12;
        for (size_t i=0;i<12;++i) if (key==record_slot_key(i)) return length==64;
        return false;
    }
    bool fail() { prepared_=false; failed_=true; return false; }
    ShieldSendspinVault &vault_;
    ShieldSendspinBlobs blobs_;
    bool bootstrap_=false;
    bool prepared_=false;
    bool failed_=false;
};
