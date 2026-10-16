#include "NativeFrameTiming.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <limits>
#include <thread>

static void verifyWholeFrameGPUInterval() {
    PGForegroundFrameTiming timing;
    auto epoch=timing.epoch();
    timing.presented(epoch,1);
    // Completion handlers can arrive out of order. Two/three command-buffer
    // durations are not the full frame's first-GPU-start to last-GPU-end span.
    timing.gpuCompleted(epoch,1.008,1.010,10,3);
    timing.gpuCompleted(epoch,1.025,1.026,11,2);
    timing.gpuCompleted(epoch,1.003,1.005,10,0);
    timing.gpuCompleted(epoch,1.020,1.021,11,0);
    timing.gpuCompleted(epoch,1.000,1.002,10,0);
    timing.gpuCompleted(epoch,2.000,2.002,12,0); // Incomplete at snapshot.
    PGFrameTimingSnapshot snapshot;
    assert(timing.takeSnapshot(11,snapshot));
    assert(snapshot.gpuFrameSpan.frames==2);
    assert(std::abs(snapshot.gpuFrameSpan.totalMs-16)<.001);
    assert(std::abs(snapshot.gpuFrameSpan.maxMs-10)<.001);
    assert(std::abs(snapshot.gpuMs-10)<.001); // Buffer durations include incomplete frame 12.
    timing.gpuCompleted(epoch,2.009,2.010,12,2);
    assert(timing.takeSnapshot(22,snapshot));
    assert(snapshot.gpuFrameSpan.frames==1 && std::abs(snapshot.gpuFrameSpan.totalMs-10)<.001);
    // Only complete, valid intervals count. Dropped/unsupported timestamps
    // must not turn a partial command group into a fast completed frame.
    timing.gpuCompleted(epoch,3,3.001,13,0);
    timing.gpuCompleted(epoch,0,0,13,2);
    assert(timing.takeSnapshot(33,snapshot) && snapshot.gpuFrameSpan.frames==0);
    timing.setActive(false);timing.setActive(true);
    auto resumed=timing.epoch();
    timing.presented(resumed,100);
    timing.gpuCompleted(epoch,3.002,3.004,13,2);
    timing.gpuCompleted(resumed,100,100.001,13,1);
    assert(timing.takeSnapshot(111,snapshot));
    assert(snapshot.gpuFrameSpan.frames==1 && std::abs(snapshot.gpuFrameSpan.totalMs-1)<.001);
}

static void verifyBoundedAndConcurrentGPUIntervals() {
    PGForegroundFrameTiming timing;
    auto epoch=timing.epoch();timing.presented(epoch,1);
    for(uint64_t frame=0;frame<1000;frame++)
        timing.gpuCompleted(epoch,2+frame*.01,2.001+frame*.01,frame,0);
    timing.gpuCompleted(epoch,2.002,2.003,0,2); // Too late for bounded history.
    timing.gpuCompleted(epoch,11.992,11.993,999,2);
    PGFrameTimingSnapshot snapshot;
    assert(timing.takeSnapshot(12,snapshot));
    assert(snapshot.gpuFrameSpan.frames==1 && std::abs(snapshot.gpuFrameSpan.totalMs-3)<.001);
    std::thread callbacks[3];
    for(uint64_t frame=1000;frame<1003;frame++)callbacks[frame-1000]=std::thread([&,frame] {
        for(unsigned cb=0;cb<4;cb++) {
            double start=20+(frame-1000)*.01+cb*.002;
            timing.gpuCompleted(epoch,start,start+.001,frame,cb==3?4:0);
        }
    });
    for(auto &callback:callbacks)callback.join();
    assert(timing.takeSnapshot(30,snapshot));
    assert(snapshot.gpuFrameSpan.frames==3 && std::abs(snapshot.gpuFrameSpan.totalMs-21)<.001);
    // Concurrent handlers can also belong to the same frame, with the final
    // buffer arriving before either of the preceding completions.
    for(unsigned cb=0;cb<3;cb++)callbacks[cb]=std::thread([&,cb] {
        double start=31+cb*.002;
        timing.gpuCompleted(epoch,start,start+.001,1003,cb==2?3:0);
    });
    for(auto &callback:callbacks)callback.join();
    assert(timing.takeSnapshot(41,snapshot));
    assert(snapshot.gpuFrameSpan.frames==1 && std::abs(snapshot.gpuFrameSpan.totalMs-5)<.001);
}

static void verifyOverlappingAndSuspendedGPUIntervals() {
    PGForegroundFrameTiming timing;
    auto epoch=timing.epoch();timing.presented(epoch,1);
    timing.gpuCompleted(epoch,2,2.004,0,0);
    timing.gpuCompleted(epoch,2.002,2.006,0,2); // Span 6 ms, summed durations 8 ms.
    timing.gpuCompleted(epoch,0,0,1,0);
    timing.gpuCompleted(epoch,2.010,2.012,1,2); // Invalid first buffer excludes frame.
    PGFrameTimingSnapshot snapshot;
    assert(timing.takeSnapshot(11,snapshot));
    assert(snapshot.gpuFrameSpan.frames==1 && std::abs(snapshot.gpuFrameSpan.totalMs-6)<.001);
    timing.gpuCompleted(epoch,20,20.001,2,0);
    timing.setActive(false);timing.setActive(true);
    auto resumed=timing.epoch();timing.presented(resumed,30);
    timing.gpuCompleted(resumed,30.003,30.004,2,2); // Still expects pre-suspend buffer.
    timing.gpuCompleted(resumed,30.010,30.011,3,1); // Next complete frame succeeds.
    assert(timing.takeSnapshot(41,snapshot));
    assert(snapshot.gpuFrameSpan.frames==1 && std::abs(snapshot.gpuFrameSpan.totalMs-1)<.001);
}

int main() {
    verifyWholeFrameGPUInterval();
    verifyBoundedAndConcurrentGPUIntervals();
    verifyOverlappingAndSuspendedGPUIntervals();
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
    puts("PASS: actual presented cadence, complete multi-buffer GPU frame spans, concurrent/out-of-order callbacks, invalid timestamps, bounded history and foreground resets.");
}
