#ifndef AUDIO_SUPPORT_H
#define AUDIO_SUPPORT_H
#include <stdint.h>
#include <CoreAudioTypes/CoreAudioTypes.h>
#include "Capture.h"
typedef struct MLMeter MLMeter;
MLMeter *ml_meter_create(void);
void ml_meter_destroy(MLMeter *meter);
void ml_meter_write(MLMeter *meter, const float *const *channels, uint32_t channelCount, uint32_t frames);
void ml_meter_write_buffers(MLMeter *meter, const AudioBufferList *buffers, uint32_t frames);
float ml_meter_rms(MLMeter *meter);
float ml_meter_peak(MLMeter *meter);
uint64_t ml_meter_frames(MLMeter *meter);
void ml_meter_reset(MLMeter *meter);
#endif
