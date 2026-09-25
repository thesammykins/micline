#pragma once

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>

namespace ml {

constexpr uint32_t kRate = 48000;
constexpr uint32_t kRingFrames = 16384;
constexpr uint32_t kMaxBlock = 4096;

inline float finite(float value) { return std::isfinite(value) ? value : 0.0f; }

inline float select_sample(const float *samples, uint32_t frame, uint32_t channels,
                           uint32_t selected, bool silent) noexcept {
    if (silent || !samples || selected >= channels) return 0;
    return finite(samples[static_cast<size_t>(frame) * channels + selected]);
}

struct Meter {
    std::atomic<float> rms{0}, peak{0};
    void write(double squares, float maximum, uint32_t count) noexcept {
        rms.store(count ? static_cast<float>(std::sqrt(squares / count)) : 0,
                  std::memory_order_relaxed);
        peak.store(finite(maximum), std::memory_order_relaxed);
    }
};

class Processor {
public:
    void configure(float gainDB, float cutoff, bool highPass, bool bypass) noexcept {
        targetGain_ = std::pow(10.0f, std::clamp(gainDB, -24.0f, 12.0f) / 20.0f);
        targetPole_ = std::exp(-2.0f * 3.14159265358979323846f *
                               std::clamp(cutoff, 20.0f, 300.0f) / kRate);
        highPass_ = highPass && !bypass;
    }

    float process(float input) noexcept {
        input = finite(input);
        gain_ += (targetGain_ - gain_) * 0.0025f;
        pole_ += (targetPole_ - pole_) * 0.0025f;
        low_ = (1.0f - pole_) * input + pole_ * low_;
        float output = (highPass_ ? input - low_ : input) * gain_;
        return finite(output);
    }

    void settle() noexcept { gain_ = targetGain_; pole_ = targetPole_; }

private:
    float gain_ = 1, targetGain_ = 1, pole_ = 0, targetPole_ = 0;
    float low_ = 0;
    bool highPass_ = true;
};

// One producer/one consumer, with fractional reads. The writer never overwrites
// unread audio; the caller decides whether a full ring is fatal.
class ClockFIFO {
public:
    bool push(float value) noexcept {
        if (write_ - readBase_ >= kRingFrames) return false;
        samples_[write_ % kRingFrames] = finite(value);
        ++write_;
        return true;
    }

    bool pull(float &value) noexcept {
        uint64_t i = static_cast<uint64_t>(position_);
        if (i + 1 >= write_) return false;
        float fraction = static_cast<float>(position_ - i);
        float a = samples_[i % kRingFrames], b = samples_[(i + 1) % kRingFrames];
        value = a + (b - a) * fraction;
        double fill = static_cast<double>(write_ - i);
        double correction = std::clamp((fill - target_) * 0.0000008, -0.001, 0.001);
        ratio_ = 1.0 + correction;
        position_ += ratio_;
        readBase_ = static_cast<uint64_t>(position_);
        return true;
    }

    uint32_t size() const noexcept {
        return static_cast<uint32_t>(std::min<uint64_t>(write_ - readBase_, kRingFrames));
    }
    double ratio() const noexcept { return ratio_; }
    void prime(uint32_t frames = 2048) noexcept {
        write_ = frames; readBase_ = 0; position_ = 0; target_ = frames;
        std::fill_n(samples_.begin(), frames, 0.0f);
    }

private:
    std::array<float, kRingFrames> samples_{};
    uint64_t write_ = 0, readBase_ = 0;
    double position_ = 0, ratio_ = 1, target_ = 2048;
};

} // namespace ml
