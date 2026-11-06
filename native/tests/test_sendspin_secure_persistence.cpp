#include "sendspin_secure_persistence.hpp"
#include <cassert>
#include <vector>
struct Vault : ShieldSendspinVault {
    ShieldVaultRead result=ShieldVaultRead::MISSING;
    ShieldSendspinBlobs committed;
    bool fail_write=false;
    ShieldVaultRead read(ShieldSendspinBlobs &out) override { out=committed; return result; }
    bool replace(const ShieldSendspinBlobs &next) override {
        if (fail_write) return false;
        committed=next; result=ShieldVaultRead::OK; return true;
    }
};
int main() {
    Vault v;
    ShieldSendspinPersistence first(v);
    assert(first.prepare() && first.healthy() && !first.load_blob("keypair"));
    std::vector<uint8_t> id(32,42);
    std::vector<uint8_t> psk(32,13);
    assert(first.save_blob("keypair",id.data(),id.size()));
    assert(v.committed.empty() && !first.commit() && !first.ready());
    // A process interruption at this point leaves no partial durable record.
    ShieldSendspinPersistence after_interruption(v);
    assert(after_interruption.prepare() && !after_interruption.load_blob("keypair"));
    assert(first.save_blob("pairing_psk",psk.data(),psk.size()) && first.commit() && first.ready());
    ShieldSendspinPersistence restored(v);
    assert(restored.prepare() && restored.load_blob("keypair")==id);
    auto before=v.committed;
    v.fail_write=true;
    std::vector<uint8_t> replacement(32,21);
    assert(!restored.save_blob("keypair",replacement.data(),replacement.size()));
    assert(v.committed==before && !restored.healthy() && !restored.commit());
    assert(!restored.save_blob("keypair",id.data(),id.size()));
    v.fail_write=false;
    ShieldSendspinPersistence corrupt(v);
    v.committed["keypair"]={1};
    assert(!corrupt.prepare() && !corrupt.healthy());
    assert(v.committed["keypair"]==std::vector<uint8_t>{1});
    v.result=ShieldVaultRead::ERROR;
    ShieldSendspinPersistence unreadable(v);
    assert(!unreadable.prepare() && !unreadable.healthy());
    v.committed.clear(); v.result=ShieldVaultRead::MISSING;
    ShieldSendspinPersistence invalid(v);
    assert(invalid.prepare());
    assert(!invalid.save_blob("unrecognized",id.data(),id.size()));
    assert(v.committed.empty());
    Vault legacy;
    legacy.result=ShieldVaultRead::OK;
    legacy.committed["future_version"]={1,2};
    ShieldSendspinPersistence future(legacy);
    assert(!future.prepare() && legacy.committed.count("future_version"));
    Vault partial;
    partial.result=ShieldVaultRead::OK;
    partial.committed["keypair"]=id;
    ShieldSendspinPersistence incomplete(partial);
    assert(!incomplete.prepare() && partial.committed.count("keypair"));
    Vault psk_only;
    psk_only.result=ShieldVaultRead::OK;
    psk_only.committed["pairing_psk"]=psk;
    ShieldSendspinPersistence missing_identity(psk_only);
    assert(!missing_identity.prepare() && psk_only.committed.size()==1);
    Vault missing_psk_paired;
    missing_psk_paired.result=ShieldVaultRead::OK;
    missing_psk_paired.committed={{"keypair",id},{"rec_0",std::vector<uint8_t>(64,7)}};
    ShieldSendspinPersistence paired_partial(missing_psk_paired);
    assert(!paired_partial.prepare() && missing_psk_paired.committed.size()==2);
    Vault zero;
    zero.result=ShieldVaultRead::OK;
    zero.committed["keypair"]=id;
    zero.committed["pairing_psk"]=std::vector<uint8_t>(32,0);
    ShieldSendspinPersistence unsafe(zero);
    assert(!unsafe.prepare());
    Vault psk_first;
    ShieldSendspinPersistence reversed(psk_first);
    assert(reversed.prepare() && reversed.save_blob("pairing_psk",psk.data(),psk.size()));
    assert(psk_first.committed.empty() && !reversed.commit() && !reversed.ready());
    ShieldSendspinPersistence after_psk_interruption(psk_first);
    assert(after_psk_interruption.prepare() && !after_psk_interruption.load_blob("pairing_psk"));
    assert(reversed.save_blob("keypair",id.data(),id.size()) && reversed.ready() && reversed.commit());
    assert(psk_first.committed.size()==2 && psk_first.committed["keypair"]==id);
    Vault failed_bootstrap;
    failed_bootstrap.fail_write=true;
    ShieldSendspinPersistence bootstrap(failed_bootstrap);
    assert(bootstrap.prepare() && bootstrap.save_blob("keypair",id.data(),id.size()));
    assert(!bootstrap.save_blob("pairing_psk",psk.data(),psk.size()));
    assert(failed_bootstrap.committed.empty() && !bootstrap.ready());
    Vault record;
    record.result=ShieldVaultRead::OK;
    record.committed={{"keypair",id},{"pairing_psk",psk}};
    ShieldSendspinPersistence slots(record);
    assert(slots.prepare());
    std::vector<uint8_t> encoded(64,12), order(12,255), delay(2,0);
    assert(slots.save_blob("rec_11",encoded.data(),encoded.size()));
    assert(slots.save_blob("rec_order",order.data(),order.size()));
    assert(slots.save_blob("output_delay",delay.data(),delay.size()));
    assert(record.committed.size()==5 && slots.commit());
    assert(!slots.save_blob("rec_12",encoded.data(),encoded.size()));
    assert(record.committed.size()==5);
    Vault protected_vault;
    protected_vault.result=ShieldVaultRead::OK;
    protected_vault.committed={{"keypair",id},{"pairing_psk",psk}};
    ShieldSendspinPersistence immutable(protected_vault);
    assert(immutable.prepare());
    assert(!immutable.save_blob("keypair",replacement.data(),replacement.size()));
    assert(protected_vault.committed["keypair"]==id);
}
