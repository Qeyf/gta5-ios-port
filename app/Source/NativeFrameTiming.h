#pragma once
#include "NativeFrameMetrics.h"
#include "NativeFrameRate.h"
#include <mutex>

struct PGFrameTimingSnapshot {
    PGFrameMetricsSnapshot cadence;
    uint64_t displayed=0, gpuBuffers=0, submitted=0, missingDrawables=0;
    double p50Ms=0, gpuMs=0, drawableWaitMs=0, slotWaitMs=0, submitMs=0;
};

// Bounded local metrics shared by the render thread and Metal callbacks. Epochs
// reject late completions and the frame spanning an application suspension.
class PGForegroundFrameTiming {
    std::mutex mutex;
    bool active=true;
    uint64_t generation=0;
    double windowStart=0, lastDisplayed=0;
    PGFrameRateWindow rate;
    PGFrameMetricsWindow cadence;
    PGFrameTimingSnapshot totals;
public:
    uint64_t epoch() { std::lock_guard<std::mutex> lock(mutex); return generation; }
    void setActive(bool value) {
        std::lock_guard<std::mutex> lock(mutex);
        if(active==value)return;
        active=value;generation++;windowStart=lastDisplayed=0;
        rate={};cadence.reset();totals={};
    }
    void presented(uint64_t epoch,double seconds) {
        std::lock_guard<std::mutex> lock(mutex);
        if(!active||epoch!=generation||!std::isfinite(seconds)||seconds<=0||seconds<=lastDisplayed)return;
        if(!windowStart)windowStart=seconds;
        if(lastDisplayed)cadence.record((seconds-lastDisplayed)*1000,0,{});
        lastDisplayed=seconds;totals.displayed++;rate.record(seconds);
    }
    void gpuCompleted(uint64_t epoch,double start,double end) {
        std::lock_guard<std::mutex> lock(mutex);
        if(!active||epoch!=generation||!std::isfinite(start)||!std::isfinite(end)||start<=0||end<start)return;
        totals.gpuBuffers++;totals.gpuMs+=(end-start)*1000;
    }
    void frameCPU(uint64_t epoch,double drawableWait,double slotWait,double submit,bool missing) {
        std::lock_guard<std::mutex> lock(mutex);
        if(!active||epoch!=generation)return;
        const double values[]={drawableWait,slotWait,submit};
        for(double v:values)if(!std::isfinite(v)||v<0)return;
        totals.submitted++;totals.missingDrawables+=missing;
        totals.drawableWaitMs+=drawableWait;totals.slotWaitMs+=slotWait;totals.submitMs+=submit;
    }
    double fps(double now) {
        std::lock_guard<std::mutex> lock(mutex);
        return active&&lastDisplayed&&now-lastDisplayed<1.5?rate.rate:0;
    }
    bool takeSnapshot(double now,PGFrameTimingSnapshot &out) {
        std::lock_guard<std::mutex> lock(mutex);
        if(!active||!windowStart||!std::isfinite(now)||now-windowStart<10)return false;
        out=totals;out.cadence=cadence.snapshot();out.p50Ms=cadence.percentile(.5);
        totals={};cadence.reset();windowStart=now;return true;
    }
};
