#pragma once
#include <stdint.h>
#include <stdbool.h>
#include "NativeUpscaling.h"
#ifdef __cplusplus
extern "C" {
#endif
void PGCaptureNativeFrame(const char *name);
double PGRenderedFramesPerSecond(void);
void PGAttachMetalLayer(void *layer);
// Stop future GPU submissions before UIKit deactivates the window scene.
void PGSetGraphicsActive(bool active);
// Reclaim unused upload buffers after their GPU work has completed.
void PGTrimGraphicsMemory(void);
bool PGSupportsMetalFXSpatial(void);
// Zero selects direct native presentation. A nonzero pair is output size,
// independent of the engine's internal back buffer, applied by the render thread.
void PGSetPresentationSize(int32_t width,int32_t height);
void PGStartGraphics(void *memory,uint64_t memorySize,uint64_t ring,uint64_t ringSize,uint64_t debug);
#ifdef __cplusplus
}
#endif
