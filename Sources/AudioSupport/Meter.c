#include "AudioSupport.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>

struct MLMeter { _Atomic(float) rms; _Atomic(float) peak; _Atomic(uint64_t) frames; };
MLMeter *ml_meter_create(void) { return calloc(1, sizeof(MLMeter)); }
void ml_meter_destroy(MLMeter *m) { free(m); }
void ml_meter_reset(MLMeter *m) { atomic_store(&m->rms, 0); atomic_store(&m->peak, 0); atomic_store(&m->frames, 0); }
void ml_meter_write(MLMeter *m, const float *const *channels, uint32_t count, uint32_t frames) {
    if (!count || !frames) return;
    double sum = 0;
    float peak = 0;
    for (uint32_t c = 0; c < count; ++c) {
        for (uint32_t i = 0; i < frames; ++i) {
            float v = channels[c][i];
            if (!isfinite(v)) continue;
            sum += (double)v * v;
            peak = fmaxf(peak, fabsf(v));
        }
    }
    atomic_store_explicit(&m->rms, sqrtf(sum / ((double)count * frames)), memory_order_relaxed);
    atomic_store_explicit(&m->peak, peak, memory_order_relaxed);
    atomic_fetch_add_explicit(&m->frames, frames, memory_order_relaxed);
}
float ml_meter_rms(MLMeter *m) { return atomic_load_explicit(&m->rms, memory_order_relaxed); }
float ml_meter_peak(MLMeter *m) { return atomic_load_explicit(&m->peak, memory_order_relaxed); }
uint64_t ml_meter_frames(MLMeter *m) { return atomic_load_explicit(&m->frames, memory_order_relaxed); }
void ml_meter_write_buffers(MLMeter *m, const AudioBufferList *buffers, uint32_t frames) {
    double sum = 0;
    float peak = 0;
    uint64_t count = 0;
    for (uint32_t b = 0; b < buffers->mNumberBuffers; ++b) {
        const AudioBuffer *buffer = &buffers->mBuffers[b];
        const float *samples = buffer->mData;
        if (!samples) continue;
        uint32_t length = frames * buffer->mNumberChannels;
        if (length > buffer->mDataByteSize / sizeof(float)) length = buffer->mDataByteSize / sizeof(float);
        count += length;
        for (uint32_t i = 0; i < length; ++i) {
            float v = samples[i];
            if (!isfinite(v)) continue;
            sum += (double)v * v;
            peak = fmaxf(peak, fabsf(v));
        }
    }
    if (count) {
        atomic_store_explicit(&m->rms, sqrtf(sum / count), memory_order_relaxed);
        atomic_store_explicit(&m->peak, peak, memory_order_relaxed);
        atomic_fetch_add_explicit(&m->frames, frames, memory_order_relaxed);
    }
}
