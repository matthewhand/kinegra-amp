#include <gdnative_api_struct.gen.h>
#include <stdint.h>
#include <stdlib.h>
#include "tegra_codec.h"

/* Godot owns one Reference per decoder. No pointers leave this adapter, and
 * all methods are called on the owning Godot main thread. */
static const godot_gdnative_core_api_struct *api;
static const godot_gdnative_ext_nativescript_api_struct *ns;
typedef struct { tm_decoder *decoder; int error; } Codec;

static void *GDCALLINGCONV create(godot_object *object, void *data) {
    (void)object; (void)data;
    return calloc(1, sizeof(Codec));
}
static void GDCALLINGCONV destroy(godot_object *object, void *data, void *user) {
    (void)object; (void)data;
    Codec *codec = user;
    if (codec) { tm_destroy(codec->decoder); free(codec); }
}

static godot_variant integer(int value) {
    godot_variant result;
    api->godot_variant_new_int(&result, value);
    return result;
}
static godot_variant bytes(const int16_t *samples, int frames) {
    godot_pool_byte_array array;
    api->godot_pool_byte_array_new(&array);
    if (frames > 0) {
        api->godot_pool_byte_array_resize(&array, frames * 4);
        godot_pool_byte_array_write_access *access = api->godot_pool_byte_array_write(&array);
        uint8_t *target = api->godot_pool_byte_array_write_access_ptr(access);
        for (int i = 0; i < frames * 2; ++i) {
            target[i * 2] = (uint16_t)samples[i] & 255;
            target[i * 2 + 1] = ((uint16_t)samples[i] >> 8) & 255;
        }
        api->godot_pool_byte_array_write_access_destroy(access);
    }
    godot_variant result;
    api->godot_variant_new_pool_byte_array(&result, &array);
    api->godot_pool_byte_array_destroy(&array);
    return result;
}

enum { OPEN, PUSH, PULL, RATE, CHANNELS, QUEUED, FINISH, CLOSE, ERROR };
static godot_variant GDCALLINGCONV method(godot_object *object, void *data,
        void *user, int argc, godot_variant **argv) {
    (void)object;
    Codec *codec = user;
    int operation = (int)(intptr_t)data;
    if (!codec) return integer(-1);
    if (operation == OPEN) {
        godot_int raw_format = argc == 1 && api->godot_variant_get_type(argv[0]) == GODOT_VARIANT_TYPE_INT ? api->godot_variant_as_int(argv[0]) : 0;
        int format = raw_format == 1 ? 1 : (raw_format == 2 ? 2 : 0);
        int ok = !codec->decoder && (format == 1 || format == 2);
        if (ok) codec->decoder = tm_create(format);
        godot_variant result;
        api->godot_variant_new_bool(&result, ok && codec->decoder != NULL);
        codec->error = 0;
        return result;
    }
    if (operation == CLOSE) {
        tm_destroy(codec->decoder); codec->decoder = NULL; codec->error = 0;
        return integer(0);
    }
    if (operation == ERROR) return integer(codec->decoder ? tm_error(codec->decoder) : codec->error);
    if (!codec->decoder) return operation == PULL ? bytes(NULL, 0) : integer(-1);
    if (operation == PUSH) {
        if (argc != 1 || api->godot_variant_get_type(argv[0]) != GODOT_VARIANT_TYPE_POOL_BYTE_ARRAY)
            return integer(-1);
        godot_pool_byte_array array = api->godot_variant_as_pool_byte_array(argv[0]);
        int size = api->godot_pool_byte_array_size(&array);
        int result = -1;
        if (size > 0 && size <= 8192) {
            godot_pool_byte_array_read_access *access = api->godot_pool_byte_array_read(&array);
            result = tm_push(codec->decoder, api->godot_pool_byte_array_read_access_ptr(access), (size_t)size);
            api->godot_pool_byte_array_read_access_destroy(access);
        }
        api->godot_pool_byte_array_destroy(&array);
        return integer(result);
    }
    if (operation == PULL) {
        godot_int raw_frames = argc == 1 && api->godot_variant_get_type(argv[0]) == GODOT_VARIANT_TYPE_INT ? api->godot_variant_as_int(argv[0]) : 0;
        int frames = raw_frames >= 1 && raw_frames <= 1024 ? (int)raw_frames : 0;
        if (frames < 1 || frames > 1024) return bytes(NULL, 0);
        int16_t pcm[1024 * 2];
        int result = tm_pull(codec->decoder, pcm, (size_t)frames);
        codec->error = result < 0 ? result : 0;
        return bytes(pcm, result > 0 ? result : 0);
    }
    if (operation == RATE) return integer(tm_sample_rate(codec->decoder));
    if (operation == CHANNELS) return integer(tm_channels(codec->decoder));
    if (operation == QUEUED) return integer((int)tm_buffered_input(codec->decoder));
    if (operation == FINISH) { tm_finish(codec->decoder); return integer(0); }
    return integer(-1);
}

GDN_EXPORT void GDCALLINGCONV godot_gdnative_init(godot_gdnative_init_options *options) {
    api = options->api_struct;
    for (unsigned int i = 0; i < api->num_extensions; ++i)
        if (api->extensions[i]->type == GDNATIVE_EXT_NATIVESCRIPT)
            ns = (const godot_gdnative_ext_nativescript_api_struct *)api->extensions[i];
}
GDN_EXPORT void GDCALLINGCONV godot_gdnative_terminate(godot_gdnative_terminate_options *options) {
    (void)options; api = NULL; ns = NULL;
}
GDN_EXPORT void GDCALLINGCONV godot_nativescript_init(void *handle) {
    if (!api || !ns) return;
    godot_instance_create_func constructor = {create, NULL, NULL};
    godot_instance_destroy_func destructor = {destroy, NULL, NULL};
    ns->godot_nativescript_register_class(handle, "TegraCodec", "Reference", constructor, destructor);
    const char *names[] = {"open", "push", "pull", "rate", "channels", "queued", "finish", "close", "lastError"};
    godot_method_attributes attributes = {GODOT_METHOD_RPC_MODE_DISABLED};
    for (int i = 0; i < 9; ++i) {
        godot_instance_method callback = {method, (void *)(intptr_t)i, NULL};
        ns->godot_nativescript_register_method(handle, "TegraCodec", names[i], attributes, callback);
    }
}
