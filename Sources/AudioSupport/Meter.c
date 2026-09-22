#include "AudioSupport.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>

struct MLMeter { _Atomic(float) rms; _Atomic(float) peak; _Atomic(uint64_t) frames; };
MLMeter *ml_meter_create(void) { return calloc(1, sizeof(MLMeter)); }
void ml_meter_destroy(MLMeter *m) { free(m); }
void ml_meter_reset(MLMeter *m) { atomic_store(&m->rms, 0); atomic_store(&m->peak, 0); atomic_store(&m->frames, 0); }

static void store_peak(MLMeter *m, float peak) {
    float current = atomic_load_explicit(&m->peak, memory_order_relaxed);
    while (peak > current && !atomic_compare_exchange_weak_explicit(&m->peak, &current, peak,
        memory_order_relaxed, memory_order_relaxed)) {}
}

void ml_meter_write(MLMeter *m, const float *const *channels, uint32_t count, uint32_t frames) {
    if (!count || !frames) return;
    float rms = 0;
    float peak = 0;
    for (uint32_t c = 0; c < count; ++c) {
        if (!channels[c]) continue;
        double sum = 0;
        uint32_t finiteCount = 0;
        for (uint32_t i = 0; i < frames; ++i) {
            float v = channels[c][i];
            if (!isfinite(v)) continue;
            sum += (double)v * v;
            finiteCount += 1;
            peak = fmaxf(peak, fabsf(v));
        }
        if (finiteCount) rms = fmaxf(rms, sqrtf(sum / finiteCount));
    }
    atomic_store_explicit(&m->rms, rms, memory_order_relaxed);
    store_peak(m, peak);
    atomic_fetch_add_explicit(&m->frames, frames, memory_order_relaxed);
}
float ml_meter_rms(MLMeter *m) { return atomic_load_explicit(&m->rms, memory_order_relaxed); }
float ml_meter_peak(MLMeter *m) { return atomic_load_explicit(&m->peak, memory_order_relaxed); }
float ml_meter_take_peak(MLMeter *m) { return atomic_exchange_explicit(&m->peak, 0, memory_order_relaxed); }
uint64_t ml_meter_frames(MLMeter *m) { return atomic_load_explicit(&m->frames, memory_order_relaxed); }
void ml_meter_write_buffers(MLMeter *m, const AudioBufferList *buffers, uint32_t frames) {
    if (!frames) return;
    float rms = 0;
    float peak = 0;
    for (uint32_t b = 0; b < buffers->mNumberBuffers; ++b) {
        const AudioBuffer *buffer = &buffers->mBuffers[b];
        const float *samples = buffer->mData;
        uint32_t channels = buffer->mNumberChannels;
        if (!samples || !channels) continue;
        uint32_t availableFrames = buffer->mDataByteSize / (sizeof(float) * channels);
        uint32_t frameCount = frames < availableFrames ? frames : availableFrames;
        for (uint32_t c = 0; c < channels; ++c) {
            double sum = 0;
            uint32_t finiteCount = 0;
            for (uint32_t i = 0; i < frameCount; ++i) {
                float v = samples[i * channels + c];
                if (!isfinite(v)) continue;
                sum += (double)v * v;
                finiteCount += 1;
                peak = fmaxf(peak, fabsf(v));
            }
            if (finiteCount) rms = fmaxf(rms, sqrtf(sum / finiteCount));
        }
    }
    atomic_store_explicit(&m->rms, rms, memory_order_relaxed);
    store_peak(m, peak);
    atomic_fetch_add_explicit(&m->frames, frames, memory_order_relaxed);
}
