#pragma once
#include <stdint.h>
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
// Native Metal renderer (Source/MetalRenderer): executes the game's graphics command ring directly on Metal.
bool PGMetalRendererAvailable(void);
void PGMetalRendererAttachLayer(void *layer);
// Call on scene deactivation before entering the background, and activation.
void PGMetalRendererSetAppActive(bool active);
// Thread-safe request; completed frame upload slots are trimmed by the renderer.
void PGMetalRendererTrimMemory(void);
bool PGMetalRendererSupportsSpatialUpscaling(void);
void PGMetalRendererSetPresentationSize(int32_t width,int32_t height);
void PGStartMetalRenderer(void *memory, uint64_t memorySize, uint64_t ring, uint64_t ringSize);
double PGMetalRendererFPS(void);
void PGMetalRendererCapture(const char *name);
#ifdef __cplusplus
}
#endif
