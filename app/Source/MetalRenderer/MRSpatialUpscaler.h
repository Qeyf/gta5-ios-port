#pragma once
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#include <array>

namespace mr {
// Renderer-thread owned; one cached configuration and three tracked output
// textures. The caller ends its encoders before encoding these Apple kernels.
class SpatialUpscaler {
  id<MTLDevice> device_=nil;
  id<MTLFXSpatialScaler> spatial_=nil;
  MPSImageBilinearScale *bilinear_=nil;
  std::array<id<MTLTexture>,3> outputs_{},inputs_{};
  NSUInteger width_=0,height_=0,outputWidth_=0,outputHeight_=0;
  MTLPixelFormat format_=MTLPixelFormatInvalid;
  bool usedMetalFX_=false;
public:
  void reset();
  bool usesMetalFX() const {return usedMetalFX_;}
  id<MTLTexture> encode(id<MTLCommandBuffer> commandBuffer,id<MTLTexture> color,
                        NSUInteger outputWidth,NSUInteger outputHeight,NSUInteger slot);
};
}
