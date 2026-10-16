#pragma once
#include "NativeFrameMetrics.h"
#include "NativeFrameRate.h"
#include <mutex>

struct PGFrameTimingSnapshot {
    PGFrameMetricsSnapshot cadence;
    PGFrameMetricsSnapshot gpuFrameSpan;
    double gpuFrameP50Ms=0;
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
    PGFrameMetricsWindow gpuSpans;
    struct GPUFrame {
        uint64_t frame=UINT64_MAX,received=0,expected=0;
        double first=0,last=0;
        bool reported=false;
    };
    // The renderer has three in-flight frame slots. Keep a little bounded
    // slack for handler scheduling, and reject callbacks older than a slot.
    std::array<GPUFrame,8> gpuFrames{};
    PGFrameTimingSnapshot totals;
public:
    uint64_t epoch() { std::lock_guard<std::mutex> lock(mutex); return generation; }
    void setActive(bool value) {
        std::lock_guard<std::mutex> lock(mutex);
        if(active==value)return;
        active=value;generation++;windowStart=lastDisplayed=0;
        rate={};cadence.reset();gpuSpans.reset();gpuFrames={};totals={};
    }
    void presented(uint64_t epoch,double seconds) {
        std::lock_guard<std::mutex> lock(mutex);
        if(!active||epoch!=generation||!std::isfinite(seconds)||seconds<=0||seconds<=lastDisplayed)return;
        if(!windowStart)windowStart=seconds;
        if(lastDisplayed)cadence.record((seconds-lastDisplayed)*1000,0,{});
        lastDisplayed=seconds;totals.displayed++;rate.record(seconds);
    }
    void gpuCompleted(uint64_t epoch,double start,double end,uint64_t frame=UINT64_MAX,uint64_t expectedBuffers=0) {
        std::lock_guard<std::mutex> lock(mutex);
        if(!active||epoch!=generation||!std::isfinite(start)||!std::isfinite(end)||start<=0||end<start)return;
        totals.gpuBuffers++;totals.gpuMs+=(end-start)*1000;
        if(frame==UINT64_MAX)return; // Existing callers may report buffers only.
        auto &group=gpuFrames[frame%gpuFrames.size()];
        if(group.frame!=frame) {
            if(group.frame!=UINT64_MAX && frame<group.frame)return;
            group={};group.frame=frame;
        }
        if(group.reported)return;
        group.received++;
        if(expectedBuffers)group.expected=expectedBuffers;
        group.first=group.first ? std::min(group.first,start) : start;
        group.last=std::max(group.last,end);
        if(group.expected && group.received==group.expected) {
            // This is the frame's GPU timeline span, including inter-buffer
            // gaps/overlap. It is neither summed buffer time nor GPU occupancy.
            gpuSpans.record((group.last-group.first)*1000,0,{});
            group.reported=true;
        }
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
        out.gpuFrameSpan=gpuSpans.snapshot();out.gpuFrameP50Ms=gpuSpans.percentile(.5);
        totals={};cadence.reset();gpuSpans.reset();windowStart=now;return true;
    }
};
