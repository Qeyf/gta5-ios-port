// The app's graphics entry points (NativeGraphics.h), served by the native Metal renderer.
#include "NativeGraphics.h"
#include "MetalRenderer/MetalRenderer.h"

extern "C" void pg_log(const char *);

void PGAttachMetalLayer(void *layer) { PGMetalRendererAttachLayer(layer); }
void PGSetGraphicsActive(bool active) { PGMetalRendererSetAppActive(active); }
void PGTrimGraphicsMemory(void) { PGMetalRendererTrimMemory(); }
bool PGSupportsMetalFXSpatial(void) { return PGMetalRendererSupportsSpatialUpscaling(); }
void PGSetPresentationSize(int32_t width,int32_t height) { PGMetalRendererSetPresentationSize(width,height); }
double PGRenderedFramesPerSecond(void) { return PGMetalRendererFPS(); }
void PGCaptureNativeFrame(const char *name) { PGMetalRendererCapture(name); }
void PGStartGraphics(void *memory, uint64_t memorySize, uint64_t ring, uint64_t ringSize, uint64_t) {
	if (!PGMetalRendererAvailable()) { pg_log("The Metal shader library is missing from the app: rebuild with the game's shaders."); return; }
	PGStartMetalRenderer(memory, memorySize, ring, ringSize);
}
