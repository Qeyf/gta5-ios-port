// Test-only engine substitutes for launching the real UIKit app shell.
// Never link this file into an IPA: Source/EngineHost.c owns these APIs there.
#ifndef PG_UI_SMOKE_TEST
#error "UISmokeBridge.c is only for the simulator UI smoke test"
#endif

#include "EngineHost.h"
#include "NativeAssetPreload.h"
#include "NativeGraphics.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "UISmokeInputProbe.h"
static uint8_t probeKeys[256];
static int32_t probeButtons,probeDX,probeDY,probeWheel;
int32_t PGUISmokeMouseButtons(void){return probeButtons;}
int32_t PGUISmokeMouseDX(void){return probeDX;}
int32_t PGUISmokeMouseDY(void){return probeDY;}
int32_t PGUISmokeMouseWheel(void){return probeWheel;}
bool PGUISmokeKeyDown(uint8_t key){return probeKeys[key]!=0;}

void PGConfigureEngine(const char *const *quality, unsigned count, int width,
                       int height, int frameLimit) {
  (void)quality; (void)count; (void)width; (void)height; (void)frameLimit;
}
void PGSetStartMode(int32_t mode) { (void)mode; }
void PGSetBackBufferSize(int width, int height) { (void)width; (void)height; }
void PGSetAssetServer(const char *url) { (void)url; }
void PGSetLocalGameFolder(const char *path) { (void)path; }
bool PGUsingLocalGameFolder(void) { return false; }

void PGStartEngine(const char *manifest, const char *root, PGLogCallback log,
                   void *context) {
  (void)manifest; (void)root; (void)log; (void)context;
  fputs("UI smoke test must not materialize the game engine.\n", stderr);
  _Exit(86);
}

void PGUpdateController(PGControllerState state, double elapsed) {
  (void)state; (void)elapsed;
}
uint32_t PGCurrentTouchContext(void) { return 0; }
uint32_t PGGameStatus(void) { return 16; } // No player before engine startup.
PGControlHints PGReadControlHints(uint32_t context) {
  (void)context;
  PGControlHints hints = {0};
  return hints;
}
void PGSetKey(uint8_t key, bool down) { probeKeys[key]=down; }
void PGSetRadioWheelDirection(float x, float y, bool active) {
  (void)x; (void)y; (void)active;
}
void PGReleaseAllKeys(void) { memset(probeKeys,0,sizeof probeKeys); }
void PGMouseInput(int32_t x, int32_t y, int32_t buttons) {
  probeDX+=x;probeDY+=y;probeButtons=buttons;
}
void PGMouseWheel(int32_t notches) { probeWheel+=notches; }
void PGSetMouseFocus(bool focused, bool locked) { (void)focused; (void)locked; }
bool PGDebugReadMemory(uint64_t address, void *out, uint64_t length) {
  (void)address;
  if (out) memset(out, 0, (size_t)length);
  return false;
}
void PGUpdateVirtualPad(PGPadState state) { (void)state; }
int32_t PGLastInputDevice(void) { return -3; }
int32_t PGTargetingMode(void) { return 0; }
void PGSetTargetingMode(int32_t mode) { (void)mode; }
bool PGPauseMenuActive(void) { return false; }
void PGFillAudio(float *left, float *right, uint32_t count) {
  if (left) memset(left, 0, (size_t)count * sizeof(float));
  if (right) memset(right, 0, (size_t)count * sizeof(float));
}
uint64_t PGMemoryBudgetQueries(void) { return 0; }
uint64_t PGMemoryBudgetClamps(void) { return 0; }
void PGAssetHealth(uint64_t out[6]) { if (out) memset(out, 0, 6 * sizeof(*out)); }

bool PGApplyCheatConsole(const char *code) { (void)code; return false; }
bool PGApplyCheatGamepad(const uint16_t *buttons, unsigned count) {
  (void)buttons; (void)count;
  return false;
}
bool PGIsCheatInProgress(void) { return false; }
void PGCancelCheat(void) {}
int32_t PGCheatResult(void) { return 0; }

void PGCaptureNativeFrame(const char *name) { (void)name; }
double PGRenderedFramesPerSecond(void) { return 0; }
void PGAttachMetalLayer(void *layer) { (void)layer; }
void PGSetGraphicsActive(bool active) { (void)active; }
void PGTrimGraphicsMemory(void) {}
void PGStartGraphics(void *memory, uint64_t memorySize, uint64_t ring,
                     uint64_t ringSize, uint64_t debug) {
  (void)memory; (void)memorySize; (void)ring; (void)ringSize; (void)debug;
}

void PGAssetCachePrepare(const char *manifest, const char *root) {
  (void)manifest; (void)root;
}
bool PGAssetPreloadSupported(void) { return false; }
void PGAssetPreloadMeasure(const char *filter, uint64_t *total, uint64_t *cached,
                          uint32_t *files) {
  (void)filter;
  if (total) *total = 0;
  if (cached) *cached = 0;
  if (files) *files = 0;
}
bool PGAssetPreloadStart(const char *filter, unsigned lanes) {
  (void)filter; (void)lanes;
  return false;
}
void PGAssetPreloadStop(void) {}
void PGAssetPreloadSetLanes(unsigned lanes) { (void)lanes; }
PGAssetPreloadStatus PGAssetPreloadGetStatus(void) {
  PGAssetPreloadStatus status = {0};
  return status;
}
bool PGAssetCacheRemoveAll(uint64_t *freed) {
  if (freed) *freed = 0;
  return false;
}
