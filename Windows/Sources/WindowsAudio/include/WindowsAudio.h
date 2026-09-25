#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct MLDevices MLDevices;
typedef struct MLEngine MLEngine;
// Enumeration opens no capture session. Strings live until list destruction.
MLDevices *ml_devices_create(char *error, uint32_t capacity);
void ml_devices_destroy(MLDevices *devices);
uint32_t ml_devices_count(const MLDevices *devices);
const char *ml_device_id(const MLDevices *devices, uint32_t index);
const char *ml_device_name(const MLDevices *devices, uint32_t index);
uint32_t ml_device_channels(const MLDevices *devices, uint32_t index);
int ml_device_is_input(const MLDevices *devices, uint32_t index);
int ml_device_is_cable(const MLDevices *devices, uint32_t index);

MLEngine *ml_engine_create(void);
void ml_engine_destroy(MLEngine *engine);
// Copies IDs and opens asynchronously; never chooses default endpoints.
int ml_engine_start(MLEngine *engine, const char *input_id, const char *output_id,
                    uint32_t channel);
// Stops and joins the worker before returning; safe when already stopped.
void ml_engine_stop(MLEngine *engine);
void ml_engine_controls(MLEngine *engine, float gain_db, float cutoff_hz,
                        int high_pass, int bypass);
// 0 stopped, 1 opening, 2 running, 3 failed. Failed workers are joined on stop.
int ml_engine_state(const MLEngine *engine);
void ml_engine_error(const MLEngine *engine, char *error, uint32_t capacity);
typedef struct MLMeters {
    float input_rms, input_peak, output_rms, output_peak;
    uint64_t underruns, overruns;
} MLMeters;
MLMeters ml_engine_meters(MLEngine *engine);
// Deterministic, offline DSP regression suite. Never opens a device or saves PCM.
int ml_audio_self_test(char *error, uint32_t capacity);
#ifdef __cplusplus
}
#endif
