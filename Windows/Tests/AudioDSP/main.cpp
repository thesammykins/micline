#include "../../Sources/WindowsAudio/include/WindowsAudio.h"
#include <cstdio>
int main() { char error[256]{}; if (!ml_audio_self_test(error, sizeof error)) { std::fprintf(stderr, "%s\n", error); return 1; }
    std::puts("WindowsAudio portable DSP self-test passed"); return 0; }
