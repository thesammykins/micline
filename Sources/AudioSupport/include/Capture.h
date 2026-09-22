#ifndef ML_CAPTURE_H
#define ML_CAPTURE_H
#include <CoreAudioTypes/CoreAudioTypes.h>
#include <stdint.h>
typedef struct MLCapture MLCapture;
MLCapture *ml_capture_create(uint32_t capacity, double sampleRate);
void ml_capture_destroy(MLCapture *capture);
void ml_capture_write(MLCapture *capture, const AudioBufferList *buffers, uint32_t frames, double hostSeconds, int64_t sampleTime);
uint32_t ml_capture_count(MLCapture *capture);
const float *ml_capture_samples(MLCapture *capture);
double ml_capture_start(MLCapture *capture);
uint32_t ml_capture_discontinuities(MLCapture *capture);
#endif
