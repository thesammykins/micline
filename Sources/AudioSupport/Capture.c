#include "Capture.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <math.h>

struct MLCapture {
    uint32_t capacity;
    double rate;
    double start;
    int64_t nextSample;
    _Atomic(uint32_t) count;
    _Atomic(uint32_t) discontinuities;
    float *samples;
};
MLCapture *ml_capture_create(uint32_t capacity, double rate) {
    MLCapture *c = calloc(1, sizeof(MLCapture));
    if (!c) return NULL;
    c->samples = calloc(capacity, sizeof(float));
    if (!c->samples) { free(c); return NULL; }
    c->capacity = capacity; c->rate = rate;
    return c;
}
void ml_capture_destroy(MLCapture *c) { free(c->samples); free(c); }
void ml_capture_write(MLCapture *c, const AudioBufferList *buffers, uint32_t frames, double hostSeconds, int64_t sampleTime) {
    uint32_t count = atomic_load_explicit(&c->count, memory_order_relaxed);
    if (!buffers->mNumberBuffers || count >= c->capacity || !frames) return;
    const AudioBuffer *b = &buffers->mBuffers[0];
    if (!b->mData || !b->mNumberChannels) return;
    uint32_t available = b->mDataByteSize / (sizeof(float) * b->mNumberChannels);
    if (frames > available) frames = available;
    if (!count) { c->start = hostSeconds; }
    else if (sampleTime != c->nextSample) { atomic_fetch_add(&c->discontinuities, 1); }
    if (!isfinite(hostSeconds) || hostSeconds <= 0) atomic_fetch_add(&c->discontinuities, 1);
    c->nextSample = sampleTime + frames;
    if (frames > c->capacity - count) frames = c->capacity - count;
    const float *source = b->mData;
    for (uint32_t i = 0; i < frames; ++i) c->samples[count + i] = source[i * b->mNumberChannels];
    atomic_store_explicit(&c->count, count + frames, memory_order_release);
}
uint32_t ml_capture_count(MLCapture *c) { return atomic_load_explicit(&c->count, memory_order_acquire); }
const float *ml_capture_samples(MLCapture *c) { return c->samples; }
double ml_capture_start(MLCapture *c) { return c->start; }
uint32_t ml_capture_discontinuities(MLCapture *c) { return atomic_load(&c->discontinuities); }
