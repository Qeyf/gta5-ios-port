// Runs the real Apple kernels. A Linux portable-check pass cannot replace it.
#include "../Source/MetalRenderer/MRSpatialUpscaler.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <initializer_list>
#include <vector>

static id<MTLTexture> input(id<MTLDevice> device,MTLPixelFormat format,NSUInteger width,NSUInteger height,bool readUsage) {
  MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:width height:height mipmapped:NO];
  d.storageMode=MTLStorageModeShared;
  d.usage=MTLTextureUsageRenderTarget|(readUsage ? MTLTextureUsageShaderRead : 0);
  id<MTLTexture> t=[device newTextureWithDescriptor:d];assert(t);
  std::vector<uint8_t> bytes(width*height*4,0);
  for(NSUInteger i=0;i<width*height;i++) {bytes[i*4+(format==MTLPixelFormatRGBA8Unorm ? 0 : 2)]=255;bytes[i*4+3]=255;}
  [t replaceRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0 withBytes:bytes.data() bytesPerRow:width*4];
  return t;
}

static void verify(id<MTLCommandBuffer> cb,id<MTLTexture> out) {
  assert(out && out.storageMode==MTLStorageModePrivate);
  assert(out.pixelFormat==MTLPixelFormatBGRA8Unorm && (out.usage&MTLTextureUsageShaderRead));
  NSUInteger pitch=(out.width*4+255)&~255u;
  id<MTLBuffer> bytes=[out.device newBufferWithLength:pitch*out.height options:MTLResourceStorageModeShared];assert(bytes);
  id<MTLBlitCommandEncoder> e=[cb blitCommandEncoder];
  [e copyFromTexture:out sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(out.width,out.height,1)
    toBuffer:bytes destinationOffset:0 destinationBytesPerRow:pitch destinationBytesPerImage:0];
  [e endEncoding];[cb commit];[cb waitUntilCompleted];
  assert(cb.status==MTLCommandBufferStatusCompleted);
  const uint8_t *p=(const uint8_t *)bytes.contents;
  for(NSUInteger y=0;y<out.height;y++)for(NSUInteger x=0;x<out.width;x++) {
    const uint8_t *c=p+y*pitch+x*4;
    // The app's CAMetalLayer is opaque; validate the displayed RGB values.
    assert(c[0]<=4 && c[1]<=4 && c[2]>=251);
  }
}

int main() {@autoreleasepool {
  id<MTLDevice> device=MTLCreateSystemDefaultDevice();
  if(!device || ![MTLFXSpatialScalerDescriptor supportsDevice:device]) {
    puts("SKIP: this host has no MetalFX-capable GPU; physical Apple GPU validation remains required.");return 77;
  }
  id<MTLCommandQueue> queue=[device newCommandQueue];assert(queue);
  mr::SpatialUpscaler scaler;
  for(MTLPixelFormat format:{MTLPixelFormatRGBA8Unorm,MTLPixelFormatBGRA8Unorm})for(bool readUsage:{true,false}) {
    id<MTLTexture> source=input(device,format,384,216,readUsage);
    id<MTLTexture> cached=nil;
    for(unsigned frame=0;frame<6;frame++) {
      id<MTLCommandBuffer> cb=[queue commandBuffer];
      id<MTLTexture> out=scaler.encode(cb,source,768,432,frame%3);
      assert(out.width==768 && out.height==432 && scaler.usesMetalFX());
      if(frame==0)cached=out;
      if(frame==3)assert(out==cached);
      verify(cb,out);
    }
    // A live resolution reduction can reach PRESENT before the engine resizes.
    id<MTLCommandBuffer> cb=[queue commandBuffer];
    id<MTLTexture> down=scaler.encode(cb,source,320,180,0);
    assert(down.width==320 && down.height==180 && !scaler.usesMetalFX());
    verify(cb,down);
    assert(!scaler.encode([queue commandBuffer],source,384,216,0));
  }
  id<MTLTexture> source=input(device,MTLPixelFormatRGBA8Unorm,384,216,true);
  id<MTLCommandBuffer> first=[queue commandBuffer],second=[queue commandBuffer];
  id<MTLTexture> old=scaler.encode(first,source,768,432,0);
  id<MTLTexture> resized=scaler.encode(second,source,640,360,0);
  // Replacing cached scalers/resources must not invalidate already encoded work.
  verify(first,old);verify(second,resized);
  puts("PASS: real MetalFX spatial scaling, RGBA/BGRA colors, required input usage, private output reuse and MPS resize fallback.");
  return 0;
}}
