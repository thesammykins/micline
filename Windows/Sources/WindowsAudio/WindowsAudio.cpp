#include "include/WindowsAudio.h"
#include "AudioDSP.hpp"

#include <atomic>
#include <cstring>
#include <cstdio>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#include <initguid.h>
#include <audioclient.h>
#include <avrt.h>
#include <functiondiscoverykeys_devpkey.h>
#include <ks.h>
#include <ksmedia.h>
#include <mmdeviceapi.h>
#include <propvarutil.h>
#include <wrl/client.h>
using Microsoft::WRL::ComPtr;
#endif

namespace {
void copy_error(char *out, uint32_t capacity, const char *text) noexcept {
    if (!out || !capacity) return;
    std::strncpy(out, text ? text : "", capacity - 1);
    out[capacity - 1] = 0;
}

struct Device { std::string id, name; uint32_t channels = 0, channelMask = 0; bool input = false, cable = false; };
}

struct MLDevices { std::vector<Device> values; };

struct MLEngine {
    std::atomic<int> state{0};
    std::atomic<float> gain{0}, cutoff{80};
    std::atomic<bool> highPass{true}, bypass{false};
    std::atomic<float> inputRMS{0}, inputPeak{0}, outputRMS{0}, outputPeak{0};
    std::atomic<uint64_t> underruns{0}, overruns{0};
    std::thread worker;
    std::mutex lifecycle, errorLock;
    std::string error;
    ml::ClockFIFO fifo;
#ifdef _WIN32
    HANDLE cancel = CreateEventW(nullptr, TRUE, FALSE, nullptr);
#else
    void *cancel = nullptr;
#endif
};

#ifdef _WIN32
namespace {
std::string utf8(const wchar_t *value) {
    if (!value) return {};
    int n = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, nullptr, 0, nullptr, nullptr);
    if (!n) return {};
    std::string result(static_cast<size_t>(n), 0);
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, result.data(), n, nullptr, nullptr);
    result.resize(static_cast<size_t>(n - 1));
    return result;
}
std::wstring wide(const char *value) {
    if (!value) return {};
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, nullptr, 0);
    if (!n) return {};
    std::wstring result(static_cast<size_t>(n), 0);
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, result.data(), n);
    result.resize(static_cast<size_t>(n - 1));
    return result;
}
std::wstring property(IPropertyStore *store, REFPROPERTYKEY key) {
    PROPVARIANT value; PropVariantInit(&value);
    std::wstring result;
    if (SUCCEEDED(store->GetValue(key, &value)) && value.vt == VT_LPWSTR && value.pwszVal)
        result = value.pwszVal;
    PropVariantClear(&value);
    return result;
}

bool endpoint_info(IMMDevice *device, EDataFlow flow, Device &out) {
    ComPtr<IMMEndpoint> endpoint;
    if (FAILED(device->QueryInterface(IID_PPV_ARGS(&endpoint)))) return false;
    EDataFlow actual;
    if (FAILED(endpoint->GetDataFlow(&actual)) || actual != flow) return false;
    LPWSTR id = nullptr;
    ComPtr<IPropertyStore> store;
    if (FAILED(device->GetId(&id)) || FAILED(device->OpenPropertyStore(STGM_READ, &store))) {
        CoTaskMemFree(id); return false;
    }
    std::wstring name = property(store.Get(), PKEY_Device_FriendlyName);
    std::wstring desc = property(store.Get(), PKEY_Device_DeviceDesc);
    out.id = utf8(id); out.name = utf8(name.c_str()); out.input = flow == eCapture;
    CoTaskMemFree(id);
    ComPtr<IAudioClient> client;
    WAVEFORMATEX *mix = nullptr;
    if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                reinterpret_cast<void **>(client.GetAddressOf()))) ||
        FAILED(client->GetMixFormat(&mix))) return false;
    out.channels = mix->nChannels;
    if (mix->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
        mix->cbSize >= sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX))
        out.channelMask = reinterpret_cast<WAVEFORMATEXTENSIBLE *>(mix)->dwChannelMask;
    CoTaskMemFree(mix);
    out.cable = flow == eRender && name == L"CABLE Input (VB-Audio Virtual Cable)" &&
                desc.find(L"VB-Audio") != std::wstring::npos;
    return !out.id.empty() && !out.name.empty() && out.channels;
}

void fail(MLEngine *engine, const char *message) {
    { std::lock_guard<std::mutex> guard(engine->errorLock); engine->error = message; }
    engine->state.store(3, std::memory_order_release);
}

struct Session {
    ComPtr<IMMDevice> inDevice, outDevice;
    ComPtr<IAudioClient> inClient, outClient;
    ComPtr<IAudioCaptureClient> capture;
    ComPtr<IAudioRenderClient> render;
    HANDLE inEvent = nullptr, outEvent = nullptr;
    WAVEFORMATEXTENSIBLE inFormat{}, outFormat{};
    ~Session() {
        if (inClient) inClient->Stop(); if (outClient) outClient->Stop();
        if (inEvent) CloseHandle(inEvent); if (outEvent) CloseHandle(outEvent);
    }
};

HRESULT open_client(IMMDevice *device, HANDLE event, WAVEFORMATEXTENSIBLE &format,
                    IAudioClient **clientOut) {
    ComPtr<IAudioClient> client;
    HRESULT hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                  reinterpret_cast<void **>(client.GetAddressOf()));
    if (FAILED(hr)) return hr;
    format.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
    format.Format.nSamplesPerSec = ml::kRate; format.Format.wBitsPerSample = 32;
    format.Format.nBlockAlign = format.Format.nChannels * 4;
    format.Format.nAvgBytesPerSec = format.Format.nBlockAlign * format.Format.nSamplesPerSec;
    format.Format.cbSize = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
    format.Samples.wValidBitsPerSample = 32;
    format.SubFormat = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
    hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM |
        AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY, 0, 0, &format.Format, nullptr);
    if (FAILED(hr) || FAILED(hr = client->SetEventHandle(event))) return hr;
    *clientOut = client.Detach(); return S_OK;
}

void run_engine(MLEngine *engine, std::wstring inputID, std::wstring outputID, uint32_t channel) {
    HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(com)) { fail(engine, "COM MTA initialization failed"); return; }
    struct COMGuard { ~COMGuard() { CoUninitialize(); } } comGuard;
    Session s; HRESULT hr = E_FAIL;
    do {
        ComPtr<IMMDeviceEnumerator> enumerator;
        if (FAILED(hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                        IID_PPV_ARGS(&enumerator)))) break;
        if (FAILED(hr = enumerator->GetDevice(inputID.c_str(), &s.inDevice)) ||
            FAILED(hr = enumerator->GetDevice(outputID.c_str(), &s.outDevice))) break;
        Device in, out;
        if (!endpoint_info(s.inDevice.Get(), eCapture, in) ||
            !endpoint_info(s.outDevice.Get(), eRender, out) || !out.cable || channel >= in.channels) {
            hr = E_INVALIDARG; break;
        }
        s.inEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        s.outEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        if (!s.inEvent || !s.outEvent) { hr = HRESULT_FROM_WIN32(GetLastError()); break; }
        s.inFormat.Format.nChannels = static_cast<WORD>(in.channels);
        s.inFormat.dwChannelMask = in.channelMask;
        s.outFormat.Format.nChannels = 2;
        s.outFormat.dwChannelMask = SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT;
        if (FAILED(hr = open_client(s.inDevice.Get(), s.inEvent, s.inFormat, s.inClient.GetAddressOf())) ||
            FAILED(hr = open_client(s.outDevice.Get(), s.outEvent, s.outFormat, s.outClient.GetAddressOf())) ||
            FAILED(hr = s.inClient->GetService(IID_PPV_ARGS(&s.capture))) ||
            FAILED(hr = s.outClient->GetService(IID_PPV_ARGS(&s.render)))) break;
        UINT32 outputFrames = 0;
        if (FAILED(hr = s.outClient->GetBufferSize(&outputFrames))) break;
        if (!outputFrames || outputFrames > ml::kMaxBlock) { hr = AUDCLNT_E_BUFFER_SIZE_ERROR; break; }
        BYTE *initial = nullptr;
        if (FAILED(hr = s.render->GetBuffer(outputFrames, &initial)) ||
            FAILED(hr = s.render->ReleaseBuffer(outputFrames, AUDCLNT_BUFFERFLAGS_SILENT))) break;
        if (WaitForSingleObject(engine->cancel, 0) == WAIT_OBJECT_0) { hr = S_OK; break; }
        if (FAILED(hr = s.outClient->Start()) || FAILED(hr = s.inClient->Start())) break;

        ml::Processor dsp; engine->fifo.prime();
        DWORD taskIndex = 0;
        HANDLE mmcss = AvSetMmThreadCharacteristicsW(L"Pro Audio", &taskIndex);
        engine->state.store(2, std::memory_order_release);
        HANDLE events[] = {engine->cancel, s.inEvent, s.outEvent};
        uint32_t consecutiveFaults = 0;
        bool firstPacket = true;
        while (true) {
            DWORD wait = WaitForMultipleObjects(3, events, FALSE, 2000);
            if (wait == WAIT_OBJECT_0) { hr = S_OK; break; }
            if (wait == WAIT_TIMEOUT || wait == WAIT_FAILED) { hr = AUDCLNT_E_DEVICE_INVALIDATED; break; }
            dsp.configure(engine->gain.load(), engine->cutoff.load(), engine->highPass.load(), engine->bypass.load());
            if (wait == WAIT_OBJECT_0 + 1) {
                UINT32 packet = 0;
                while (SUCCEEDED(hr = s.capture->GetNextPacketSize(&packet)) && packet) {
                    BYTE *data = nullptr; UINT32 frames = 0; DWORD flags = 0;
                    if (FAILED(hr = s.capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) break;
                    // Windows may mark the first packet discontinuous at stream startup.
                    if (!firstPacket && (flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY)) {
                        s.capture->ReleaseBuffer(frames); hr = AUDCLNT_E_DEVICE_INVALIDATED; break;
                    }
                    firstPacket = false;
                    double inSquares = 0, outSquares = 0; float inPeak = 0, outPeak = 0;
                    const float *samples = reinterpret_cast<const float *>(data);
                    for (UINT32 i = 0; i < frames; ++i) {
                        float input = ml::select_sample(samples, i, in.channels, channel,
                                                       (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0);
                        float output = dsp.process(input);
                        inSquares += input * input; outSquares += output * output;
                        inPeak = std::max(inPeak, std::fabs(input)); outPeak = std::max(outPeak, std::fabs(output));
                        if (!engine->fifo.push(output)) { engine->overruns.fetch_add(1); ++consecutiveFaults; }
                    }
                    engine->inputRMS.store(frames ? std::sqrt(inSquares / frames) : 0); engine->inputPeak.store(inPeak);
                    engine->outputRMS.store(frames ? std::sqrt(outSquares / frames) : 0); engine->outputPeak.store(outPeak);
                    if (FAILED(hr = s.capture->ReleaseBuffer(frames))) break;
                }
                if (FAILED(hr)) break;
            } else {
                UINT32 padding = 0;
                if (FAILED(hr = s.outClient->GetCurrentPadding(&padding))) break;
                if (padding > outputFrames) { hr = AUDCLNT_E_BUFFER_ERROR; break; }
                UINT32 frames = outputFrames - padding;
                BYTE *bytes = nullptr;
                if (frames && FAILED(hr = s.render->GetBuffer(frames, &bytes))) break;
                float *samples = reinterpret_cast<float *>(bytes);
                bool starved = false;
                for (UINT32 i = 0; i < frames; ++i) {
                    float value = 0; if (!engine->fifo.pull(value)) starved = true;
                    samples[i * 2] = samples[i * 2 + 1] = value;
                }
                if (frames && FAILED(hr = s.render->ReleaseBuffer(frames, 0))) break;
                if (starved) { engine->underruns.fetch_add(1); ++consecutiveFaults; }
                else consecutiveFaults = 0;
            }
            if (consecutiveFaults > 200) { hr = AUDCLNT_E_BUFFER_ERROR; break; }
        }
        if (mmcss) AvRevertMmThreadCharacteristics(mmcss);
    } while (false);
    if (FAILED(hr) && engine->state.load() != 0) {
        char detail[180];
        std::snprintf(detail, sizeof detail, "WASAPI stopped (0x%08lx). Check selected devices and microphone privacy settings; then Rescan.",
                      static_cast<unsigned long>(hr));
        fail(engine, detail);
    }
}
}
#endif

extern "C" {
MLDevices *ml_devices_create(char *error, uint32_t capacity) {
    copy_error(error, capacity, "");
    try {
        auto result = std::make_unique<MLDevices>();
#ifdef _WIN32
        HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        if (FAILED(com)) { copy_error(error, capacity, "COM initialization failed"); return nullptr; }
        struct COMGuard { ~COMGuard() { CoUninitialize(); } } comGuard;
        ComPtr<IMMDeviceEnumerator> enumerator;
        HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
        for (EDataFlow flow : {eCapture, eRender}) {
            ComPtr<IMMDeviceCollection> collection;
            if (FAILED(hr) || FAILED(hr = enumerator->EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE, &collection))) break;
            UINT count = 0; collection->GetCount(&count);
            for (UINT i = 0; i < count; ++i) { ComPtr<IMMDevice> d; Device info;
                if (SUCCEEDED(collection->Item(i, &d)) && endpoint_info(d.Get(), flow, info)) result->values.push_back(std::move(info)); }
        }
        if (FAILED(hr)) { copy_error(error, capacity, "Audio endpoint enumeration failed"); return nullptr; }
#endif
        return result.release();
    } catch (...) { copy_error(error, capacity, "Out of memory enumerating devices"); return nullptr; }
}
void ml_devices_destroy(MLDevices *d) { delete d; }
uint32_t ml_devices_count(const MLDevices *d) { return d ? static_cast<uint32_t>(d->values.size()) : 0; }
const char *ml_device_id(const MLDevices *d, uint32_t i) { return d && i < d->values.size() ? d->values[i].id.c_str() : nullptr; }
const char *ml_device_name(const MLDevices *d, uint32_t i) { return d && i < d->values.size() ? d->values[i].name.c_str() : nullptr; }
uint32_t ml_device_channels(const MLDevices *d, uint32_t i) { return d && i < d->values.size() ? d->values[i].channels : 0; }
int ml_device_is_input(const MLDevices *d, uint32_t i) { return d && i < d->values.size() && d->values[i].input; }
int ml_device_is_cable(const MLDevices *d, uint32_t i) { return d && i < d->values.size() && d->values[i].cable; }

MLEngine *ml_engine_create(void) { try {
    auto engine = new MLEngine;
#ifdef _WIN32
    if (!engine->cancel) { delete engine; return nullptr; }
#endif
    return engine;
} catch (...) { return nullptr; } }
void ml_engine_stop(MLEngine *e) {
    if (!e) return;
    std::lock_guard<std::mutex> guard(e->lifecycle);
#ifdef _WIN32
    SetEvent(e->cancel);
#endif
    if (e->worker.joinable()) e->worker.join();
    e->state.store(0); e->inputRMS.store(0); e->inputPeak.store(0); e->outputRMS.store(0); e->outputPeak.store(0);
}
void ml_engine_destroy(MLEngine *e) { if (!e) return; ml_engine_stop(e);
#ifdef _WIN32
    if (e->cancel) CloseHandle(e->cancel);
#endif
    delete e;
}
int ml_engine_start(MLEngine *e, const char *input, const char *output, uint32_t channel) {
    if (!e || !input || !output) return 0;
    try {
        std::lock_guard<std::mutex> guard(e->lifecycle);
        if (e->worker.joinable() || e->state.load() != 0) return 0;
#ifdef _WIN32
        std::wstring in = wide(input), out = wide(output); if (in.empty() || out.empty()) return 0;
        ResetEvent(e->cancel); e->underruns.store(0); e->overruns.store(0); e->state.store(1);
        e->worker = std::thread([e, in = std::move(in), out = std::move(out), channel]() mutable {
            try { run_engine(e, std::move(in), std::move(out), channel); }
            catch (...) { fail(e, "Unexpected audio worker failure"); }
        });
        return 1;
#else
        (void)channel; return 0;
#endif
    } catch (...) { e->state.store(3); std::lock_guard<std::mutex> error(e->errorLock); e->error = "Could not start audio worker"; return 0; }
}
void ml_engine_controls(MLEngine *e, float gain, float cutoff, int hp, int bypass) { if (!e) return;
    e->gain.store(std::clamp(ml::finite(gain), -24.0f, 12.0f)); e->cutoff.store(std::clamp(ml::finite(cutoff), 20.0f, 300.0f));
    e->highPass.store(hp != 0); e->bypass.store(bypass != 0); }
int ml_engine_state(const MLEngine *e) { return e ? e->state.load() : 0; }
void ml_engine_error(const MLEngine *e, char *out, uint32_t capacity) { if (!e || e->state.load() != 3) { copy_error(out, capacity, ""); return; }
    std::lock_guard<std::mutex> guard(const_cast<MLEngine *>(e)->errorLock); copy_error(out, capacity, e->error.c_str()); }
MLMeters ml_engine_meters(MLEngine *e) { MLMeters m{}; if (!e) return m; m.input_rms=e->inputRMS.load(); m.input_peak=e->inputPeak.load();
    m.output_rms=e->outputRMS.load(); m.output_peak=e->outputPeak.load(); m.underruns=e->underruns.load(); m.overruns=e->overruns.load(); return m; }

int ml_audio_self_test(char *error, uint32_t capacity) {
    copy_error(error, capacity, "");
    auto check = [&](bool ok, const char *message) { if (!ok) copy_error(error, capacity, message); return ok; };
    ml::Processor dsp; dsp.configure(6.0205999f, 80, true, true); dsp.settle();
    if (!check(std::fabs(dsp.process(0.25f) - 0.5f) < .0002f, "bypass did not retain gain")) return 0;
    if (!check(dsp.process(INFINITY) == 0, "nonfinite sample was not sanitized")) return 0;
    auto response = [](float frequency) { ml::Processor p; p.configure(0, 80, true, false); p.settle(); double sum=0;
        for (uint32_t i=0;i<ml::kRate*2;i++) { float y=p.process(std::sin(2*3.14159265358979323846*frequency*i/ml::kRate)); if(i>=ml::kRate) sum+=y*y; }
        return std::sqrt(sum/ml::kRate); };
    if (!check(response(20) < .20 && response(4000) > .65, "high-pass frequency response failed")) return 0;
    for (double ppm : {-500.0, 500.0}) { ml::ClockFIFO fifo; fifo.prime(); double produced=0;
        float v = 0;
        for (uint32_t i=0;i<180*ml::kRate;i++) { produced += 1.0 + ppm/1000000.0; while(produced>=1) {
                if(!fifo.push(.1f)) { copy_error(error, capacity, "clock FIFO overrun"); return 0; } produced-=1; }
            if(!fifo.pull(v)) { copy_error(error,capacity,"clock FIFO underrun"); return 0; } }
        if (!check(fifo.size()>1000 && fifo.size()<3100 && std::fabs(v-.1f)<.0001f &&
                   std::fabs(fifo.ratio() - (1+ppm/1000000)) < .00002,
                   "clock FIFO did not converge to the producer rate")) return 0; }
    std::array<float, ml::kMaxBlock*3> asymmetric{}; for(uint32_t i=0;i<ml::kMaxBlock;i++){ asymmetric[i*3]=.1f; asymmetric[i*3+1]=.3f; asymmetric[i*3+2]=-.8f; }
    double squares=0; float peak=0; for(uint32_t i=0;i<ml::kMaxBlock;i++){ float selected=ml::select_sample(asymmetric.data(),i,3,1,false); squares+=selected*selected; peak=std::max(peak,std::fabs(selected)); }
    if (!check(std::fabs(std::sqrt(squares/ml::kMaxBlock)-.3)<.0001 && std::fabs(peak-.3)<.0001,
               "asymmetric channel selection or meter expectation failed")) return 0;
    if (!check(ml::select_sample(asymmetric.data(), ml::kMaxBlock-1, 3, 2, false) == -.8f &&
               ml::select_sample(asymmetric.data(), 0, 3, 3, false) == 0 &&
               ml::select_sample(nullptr, 0, 3, 1, true) == 0,
               "last channel, invalid channel or silent packet failed")) return 0;
    return 1;
}
}
