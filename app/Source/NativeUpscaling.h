#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct {
  uint32_t width, height, outputWidth, outputHeight;
  bool upscaled;
} PGRenderDimensions;

// Output is the player's chosen resolution; input must fit the engine's
// existing 320x180...3840x2160 back-buffer contract. Modes:0 native,1 quality,2 performance.
static inline PGRenderDimensions pg_render_dimensions(int32_t width,int32_t height,int32_t mode,bool supported) {
  uint32_t w=width<320 ? 320 : width>3840 ? 3840 : (uint32_t)width&~1u;
  uint32_t h=height<180 ? 180 : height>2160 ? 2160 : (uint32_t)height&~1u;
  PGRenderDimensions d={w,h,w,h,false};
  if(!supported || (mode!=1 && mode!=2)) return d;
  uint32_t inputWidth=(mode==1 ? w*2/3 : w/2)&~1u;
  uint32_t inputHeight=(mode==1 ? h*2/3 : h/2)&~1u;
  // Preserve the aspect ratio when the requested scale is below engine limits.
  if(inputWidth<320 || inputHeight<180) return d;
  d.width=inputWidth;d.height=inputHeight;d.upscaled=inputWidth<w || inputHeight<h;
  return d;
}
