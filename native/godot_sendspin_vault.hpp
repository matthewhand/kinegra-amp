#pragma once
#include <gdnative_api_struct.gen.h>
#include <cstring>
#include <string>
#include "sendspin_vault_codec.hpp"
// Godot callback adapter to the purpose-scoped Android Keystore singleton.
// All SDK persistence calls happen on the Godot main thread. Store status is
// checked after every read; missing and error must never be conflated.
class GodotSendspinVault final : public ShieldSendspinVault {
public:
    GodotSendspinVault(const godot_gdnative_core_api_struct *core,const godot_variant *object) : api_(core) {
        api_->godot_variant_new_copy(&store_,object);
    }
    ~GodotSendspinVault() override { api_->godot_variant_destroy(&store_); }
    ShieldVaultRead read(ShieldSendspinBlobs &out) override {
        godot_variant value; if (!call("loadSendspinSnapshot",nullptr,0,value)) return ShieldVaultRead::ERROR;
        if (api_->godot_variant_get_type(&value)!=GODOT_VARIANT_TYPE_POOL_BYTE_ARRAY) { api_->godot_variant_destroy(&value); return ShieldVaultRead::ERROR; }
        godot_pool_byte_array array=api_->godot_variant_as_pool_byte_array(&value);
        const auto size=api_->godot_pool_byte_array_size(&array);
        std::vector<uint8_t> data;
        if (size>0 && size<=static_cast<int>(shield_sendspin_vault_codec::max_bytes)) {
            auto *r=api_->godot_pool_byte_array_read(&array);
            const uint8_t *ptr=api_->godot_pool_byte_array_read_access_ptr(r);
            data.assign(ptr,ptr+size); api_->godot_pool_byte_array_read_access_destroy(r);
        }
        api_->godot_pool_byte_array_destroy(&array); api_->godot_variant_destroy(&value);
        if (size<0 || size>static_cast<int>(shield_sendspin_vault_codec::max_bytes)) return ShieldVaultRead::ERROR;
        godot_variant status; if (!call("sendspinSnapshotStatus",nullptr,0,status)) return ShieldVaultRead::ERROR;
        if (api_->godot_variant_get_type(&status)!=GODOT_VARIANT_TYPE_STRING) { api_->godot_variant_destroy(&status); return ShieldVaultRead::ERROR; }
        godot_string str=api_->godot_variant_as_string(&status); godot_char_string text=api_->godot_string_utf8(&str);
        std::string state(api_->godot_char_string_get_data(&text),api_->godot_char_string_length(&text));
        api_->godot_char_string_destroy(&text); api_->godot_string_destroy(&str); api_->godot_variant_destroy(&status);
        if (state=="missing" && data.empty()) return ShieldVaultRead::MISSING;
        if (state!="secure" || !shield_sendspin_vault_codec::decode(data,out)) return ShieldVaultRead::ERROR;
        return ShieldVaultRead::OK;
    }
    bool replace(const ShieldSendspinBlobs &snapshot) override {
        std::vector<uint8_t> data;
        if (!shield_sendspin_vault_codec::encode(snapshot,data)) return false;
        godot_pool_byte_array array; api_->godot_pool_byte_array_new(&array); api_->godot_pool_byte_array_resize(&array,static_cast<godot_int>(data.size()));
        auto *w=api_->godot_pool_byte_array_write(&array); std::memcpy(api_->godot_pool_byte_array_write_access_ptr(w),data.data(),data.size()); api_->godot_pool_byte_array_write_access_destroy(w);
        godot_variant arg; api_->godot_variant_new_pool_byte_array(&arg,&array); api_->godot_pool_byte_array_destroy(&array);
        const godot_variant *args[]={&arg}; godot_variant result;
        const bool called=call("replaceSendspinSnapshot",args,1,result);
        api_->godot_variant_destroy(&arg);
        if (!called) return false;
        const bool ok=api_->godot_variant_get_type(&result)==GODOT_VARIANT_TYPE_BOOL && api_->godot_variant_as_bool(&result);
        api_->godot_variant_destroy(&result); return ok;
    }
private:
    bool call(const char *method,const godot_variant **args,int count,godot_variant &result) {
        godot_string name; api_->godot_string_new(&name); api_->godot_string_parse_utf8(&name,method);
        godot_variant_call_error error{}; result=api_->godot_variant_call(&store_,&name,args,count,&error); api_->godot_string_destroy(&name);
        if (error.error!=GODOT_CALL_ERROR_CALL_OK) { api_->godot_variant_destroy(&result); return false; }
        return true;
    }
    const godot_gdnative_core_api_struct *api_;
    godot_variant store_;
};
