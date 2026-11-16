#pragma once

#include "sendspin_vault_codec.hpp"
#include <jni.h>

// The application-context Keystore object is owned by the service worker.
// Create, use and destroy this adapter from that same Java thread.
class AndroidSendspinVaultAdapter final : public ShieldSendspinVault {
public:
    AndroidSendspinVaultAdapter(JNIEnv* env, jobject store) : env_(env) {
        if (!store) return;
        jclass type = env_->GetObjectClass(store);
        if (consume_exception() || !type) return;
        load_ = env_->GetMethodID(type, "load", "()[B");
        if (!consume_exception() && load_) {
            store_ = env_->GetMethodID(type, "replace", "([B)Z");
            if (!consume_exception() && store_) {
                object_ = env_->NewGlobalRef(store);
                consume_exception();
            }
        }
        env_->DeleteLocalRef(type);
    }
    ~AndroidSendspinVaultAdapter() override {
        if (object_) env_->DeleteGlobalRef(object_);
    }
    AndroidSendspinVaultAdapter(const AndroidSendspinVaultAdapter&) = delete;
    AndroidSendspinVaultAdapter& operator=(const AndroidSendspinVaultAdapter&) = delete;

    ShieldVaultRead read(ShieldSendspinBlobs& output) override {
        if (!object_) return ShieldVaultRead::ERROR;
        auto array = static_cast<jbyteArray>(env_->CallObjectMethod(object_, load_));
        if (consume_exception() || !array) return ShieldVaultRead::ERROR;
        const jsize length = env_->GetArrayLength(array);
        if (length == 0) {
            env_->DeleteLocalRef(array);
            return ShieldVaultRead::MISSING;
        }
        std::vector<uint8_t> data;
        if (length > 0 && static_cast<size_t>(length) <= shield_sendspin_vault_codec::max_bytes) {
            data.resize(length);
            env_->GetByteArrayRegion(array, 0, length, reinterpret_cast<jbyte*>(data.data()));
            if (consume_exception()) data.clear();
        }
        wipe_java_array(array, length);
        env_->DeleteLocalRef(array);
        const bool decoded = shield_sendspin_vault_codec::decode(data, output);
        wipe(data);
        return decoded ? ShieldVaultRead::OK : ShieldVaultRead::ERROR;
    }

    bool replace(const ShieldSendspinBlobs& snapshot) override {
        if (!object_) return false;
        std::vector<uint8_t> data;
        if (!shield_sendspin_vault_codec::encode(snapshot, data)) return false;
        auto array = env_->NewByteArray(static_cast<jsize>(data.size()));
        if (consume_exception() || !array) {
            wipe(data);
            return false;
        }
        env_->SetByteArrayRegion(array, 0, static_cast<jsize>(data.size()),
                                  reinterpret_cast<const jbyte*>(data.data()));
        bool replaced = false;
        if (!consume_exception()) {
            const auto result = env_->CallBooleanMethod(object_, store_, array);
            replaced = !consume_exception() && result == JNI_TRUE;
        }
        wipe_java_array(array, static_cast<jsize>(data.size()));
        env_->DeleteLocalRef(array);
        wipe(data);
        return replaced;
    }

private:
    bool consume_exception() const {
        if (!env_->ExceptionCheck()) return false;
        env_->ExceptionClear();
        return true;
    }

    static void wipe(std::vector<uint8_t>& data) {
        volatile uint8_t* ptr = data.data();
        for (size_t i = 0; i < data.size(); ++i) ptr[i] = 0;
    }

    void wipe_java_array(jbyteArray array, jsize length) const {
        if (length <= 0 || static_cast<size_t>(length) > shield_sendspin_vault_codec::max_bytes)
            return;
        const jbyte zeros[shield_sendspin_vault_codec::max_bytes] = {};
        env_->SetByteArrayRegion(array, 0, length, zeros);
        consume_exception();
    }

    JNIEnv* env_;
    jobject object_ = nullptr;
    jmethodID load_ = nullptr;
    jmethodID store_ = nullptr;
};
