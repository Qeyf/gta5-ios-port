#include "NativeFrameTiming.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <limits>
#include <thread>

int main() {
    PGForegroundFrameTiming timing;
    auto epoch = timing.epoch();
    for (int i = 0; i <= 600; ++i) {
        double seconds = 1 + i / 60.0;
        timing.presented(epoch, seconds);
        timing.gpuCompleted(epoch, seconds, seconds + .003);
        timing.frameCPU(epoch, .4, .2, .1, false);
    }
    assert(std::abs(timing.fps(11) - 60) < 0.001);
    PGFrameTimingSnapshot snapshot;
    assert(timing.takeSnapshot(11, snapshot));
    assert(snapshot.displayed == 601 && snapshot.cadence.frames == 600);
    assert(snapshot.cadence.p95Ms == 17 && snapshot.gpuBuffers == 601);
    assert(std::abs(snapshot.gpuMs - 1803) < 0.001);
    assert(std::abs(snapshot.drawableWaitMs - 240.4) < 0.001);
    assert(timing.fps(13) == 0);
    timing.setActive(false);
    timing.presented(epoch, 1000); // Late callbacks from before backgrounding.
    timing.gpuCompleted(epoch, 1000, 1001);
    timing.frameCPU(epoch, 10000, 10000, 10000, true);
    assert(timing.fps(1000) == 0);
    timing.setActive(true);
    auto resumed = timing.epoch();
    assert(resumed != epoch);
    timing.presented(epoch, 1001);
    timing.presented(resumed, 1001);
    timing.presented(resumed, 1001 + 1.0 / 120);
    timing.gpuCompleted(resumed, 0, 0); // GPU timestamps unsupported/failed.
    timing.gpuCompleted(resumed, 1001, 1000);
    timing.presented(resumed, std::numeric_limits<double>::quiet_NaN());
    timing.presented(resumed, 1000); // Out-of-order presentation callback.
    timing.frameCPU(resumed, 1, 2, 3, true);
    assert(timing.takeSnapshot(1012, snapshot));
    assert(snapshot.displayed == 2 && snapshot.cadence.frames == 1 && snapshot.gpuBuffers == 0);
    assert(snapshot.cadence.maxMs < 9 && snapshot.missingDrawables == 1);
    assert(snapshot.drawableWaitMs == 1 && snapshot.slotWaitMs == 2 && snapshot.submitMs == 3);
    // Completion callbacks and the render thread share only bounded counters.
    std::thread gpu([&] { for (int i = 0; i < 10000; ++i) timing.gpuCompleted(resumed, 20, 20.001); });
    for (int i = 0; i < 10000; ++i) timing.frameCPU(resumed, 0, 0, 0, false);
    gpu.join();
    assert(timing.takeSnapshot(1023, snapshot));
    assert(snapshot.gpuBuffers == 10000 && std::abs(snapshot.gpuMs - 10000) < .001);
    puts("PASS: actual presented cadence, GPU durations, concurrent callbacks, missing drawables, stale epochs, foreground resets and bounded windows.");
}
