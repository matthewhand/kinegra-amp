#include "android_sendspin_vault.hpp"
#include "sendspin_session.hpp"

namespace {
using shieldamp::SendspinSession;

SendspinSession* session_for(jlong handle) {
    return reinterpret_cast<SendspinSession*>(static_cast<intptr_t>(handle));
}
}

extern "C" JNIEXPORT jlong JNICALL Java_au_local_shieldamp_NativeSendspinWorker_openNative(
        JNIEnv* env, jclass, jstring endpoint, jobject vault) {
    if (!endpoint || !vault || env->GetStringUTFLength(endpoint) > 512) return 0;
    const char* text = env->GetStringUTFChars(endpoint, nullptr);
    if (!text) return 0;
    const std::string address{text};
    env->ReleaseStringUTFChars(endpoint, text);
    auto session = std::make_unique<SendspinSession>();
    auto adapter = std::make_unique<AndroidSendspinVaultAdapter>(env, vault);
    if (!session->open(address, std::move(adapter))) return 0;
    return static_cast<jlong>(reinterpret_cast<intptr_t>(session.release()));
}

extern "C" JNIEXPORT jboolean JNICALL Java_au_local_shieldamp_NativeSendspinWorker_tickNative(
        JNIEnv*, jclass, jlong handle) {
    return handle && session_for(handle)->tick() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL Java_au_local_shieldamp_NativeSendspinWorker_trustedNative(
        JNIEnv*, jclass, jlong handle) {
    return handle && session_for(handle)->is_trusted() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL Java_au_local_shieldamp_NativeSendspinWorker_closeNative(
        JNIEnv*, jclass, jlong handle) {
    delete session_for(handle);
}

extern "C" JNIEXPORT jlong JNICALL Java_au_local_shieldamp_NativeSendspinWorker_generationNative(
        JNIEnv*, jclass, jlong handle) {
    if (!handle) return -1;
    auto& session = *session_for(handle);
    if (!session.is_trusted()) return -1;
    const auto snapshot = session.audio.snapshot();
    return snapshot.active ? static_cast<jlong>(snapshot.generation) : -1;
}

extern "C" JNIEXPORT jboolean JNICALL Java_au_local_shieldamp_NativeSendspinWorker_ackNative(
        JNIEnv*, jclass, jlong handle, jlong generation) {
    return handle && generation >= 0 && session_for(handle)->is_trusted() &&
            session_for(handle)->audio.acknowledge_generation(static_cast<uint64_t>(generation))
            ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jint JNICALL Java_au_local_shieldamp_NativeSendspinWorker_readNative(
        JNIEnv* env, jclass, jlong handle, jlong generation, jobject direct, jint limit) {
    if (!handle || generation < 0 || !direct || limit < 4 || limit > 4096 || limit % 4 != 0 ||
            env->GetDirectBufferCapacity(direct) < limit)
        return -1;
    auto* bytes = static_cast<uint8_t*>(env->GetDirectBufferAddress(direct));
    if (!bytes) return -1;
    const uint64_t expected = static_cast<uint64_t>(generation);
    uint64_t observed = 0;
    size_t count = session_for(handle)->read_pcm(bytes, static_cast<size_t>(limit), observed, &expected);
    return observed == expected ? static_cast<jint>(count) : -2;
}

extern "C" JNIEXPORT jint JNICALL Java_au_local_shieldamp_NativeSendspinWorker_writeNative(
        JNIEnv* env, jclass, jlong handle, jlong generation, jobject output,
        jobject direct, jint bytes) {
    if (!handle || generation < 0 || !output || !direct || bytes <= 0 ||
        bytes > 4096 || bytes % 4 != 0 || env->GetDirectBufferCapacity(direct) < bytes)
        return -1;
    auto& session = *session_for(handle);
    if (!session.is_trusted()) return -2;
    jclass type = env->GetObjectClass(output);
    if (!type) return -1;
    jmethodID write = env->GetMethodID(type, "writePcm", "(Ljava/nio/ByteBuffer;I)I");
    env->DeleteLocalRef(type);
    if (!write) return -1;
    jint consumed = 0;
    // writePcm uses AudioTrack.WRITE_NON_BLOCKING and cannot re-enter the SDK.
    // No old-generation write may enter the backend after an ordered clear.
    bool current = session.audio.if_current_generation(static_cast<uint64_t>(generation), [&] {
        consumed = env->CallIntMethod(output, write, direct, bytes);
    });
    return current ? consumed : -2;
}

extern "C" JNIEXPORT jboolean JNICALL Java_au_local_shieldamp_NativeSendspinWorker_playedNative(
        JNIEnv*, jclass, jlong handle, jlong generation, jint frames, jlong timestamp_age_ns) {
    if (!handle || timestamp_age_ns < 0 || timestamp_age_ns > 250000000) return JNI_FALSE;
    auto& session = *session_for(handle);
    const auto finish = sendspin::SendspinClient::now_us() - timestamp_age_ns / 1000;
    return session.report_played(generation, frames, finish) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL Java_au_local_shieldamp_NativeSendspinWorker_commandNative(
        JNIEnv* env, jclass, jlong handle, jstring action, jint value) {
    if (!handle || !action || env->GetStringUTFLength(action) > 16) return JNI_FALSE;
    const char* text = env->GetStringUTFChars(action, nullptr);
    if (!text) return JNI_FALSE;
    const std::string command{text};
    env->ReleaseStringUTFChars(action, text);
    return session_for(handle)->command(command, value) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL Java_au_local_shieldamp_NativeSendspinWorker_confirmNative(
        JNIEnv*, jclass, jlong handle) {
    return handle && session_for(handle)->confirm_pairing() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jstring JNICALL Java_au_local_shieldamp_NativeSendspinWorker_snapshotNative(
        JNIEnv* env, jclass, jlong handle) {
    JsonDocument status;
    if (!handle) return env->NewStringUTF("{}");
    auto& session = *session_for(handle);
    const bool paired = session.is_trusted();
    const auto audio = session.audio.snapshot();
    status["paired"] = paired;
    status["pairing_window"] = session.listener.pairing_window;
    status["persistent"] = session.persistence != nullptr;
    status["generation"] = audio.generation;
    status["ring_bytes"] = paired && audio.active ? audio.queued_bytes : 0;
    status["client_id"] = session.client ? session.client->client_id() : "";
    const std::string& code = session.listener.code;
    if (!paired && code.size() == 6 &&
            std::all_of(code.begin(), code.end(), [](char c) { return c >= '0' && c <= '9'; })) {
        status["pairing_code"] = code;
    }
    using Command = sendspin::SendspinControllerCommand;
    status["can_play"] = paired && session.supports(Command::PLAY);
    status["can_pause"] = paired && session.supports(Command::PAUSE);
    status["can_stop"] = paired && session.supports(Command::STOP);
    status["can_next"] = paired && session.supports(Command::NEXT);
    status["can_previous"] = paired && session.supports(Command::PREVIOUS);
    std::string json;
    serializeJson(status,json);
    return env->NewStringUTF(json.c_str());
}
