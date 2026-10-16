#include "MRSpatialUpscaler.h"

namespace mr {
void SpatialUpscaler::reset() {
  spatial_=nil;bilinear_=nil;device_=nil;
  for(auto &texture:outputs_)texture=nil;
  for(auto &texture:inputs_)texture=nil;
  width_=height_=outputWidth_=outputHeight_=0;
  format_=MTLPixelFormatInvalid;usedMetalFX_=false;
}

id<MTLTexture> SpatialUpscaler::encode(id<MTLCommandBuffer> cb,id<MTLTexture> color,
                                      NSUInteger outputWidth,NSUInteger outputHeight,NSUInteger slot) {
  usedMetalFX_=false;
  // PRESENT carries the final perceptual LDR image, not a linear/HDR scene.
  // Do not guess color-space transforms for other engine texture formats.
  if(!cb || !color || !outputWidth || !outputHeight || outputWidth>8192 || outputHeight>8192 ||
     color.textureType!=MTLTextureType2D || color.sampleCount!=1 ||
     (color.pixelFormat!=MTLPixelFormatRGBA8Unorm && color.pixelFormat!=MTLPixelFormatBGRA8Unorm) ||
     (color.width==outputWidth && color.height==outputHeight)) {reset();return nil;}
  if(device_!=color.device || width_!=color.width || height_!=color.height ||
     outputWidth_!=outputWidth || outputHeight_!=outputHeight || format_!=color.pixelFormat) {
    reset();device_=color.device;width_=color.width;height_=color.height;
    outputWidth_=outputWidth;outputHeight_=outputHeight;format_=color.pixelFormat;
    if(width_<=outputWidth && height_<=outputHeight && [MTLFXSpatialScalerDescriptor supportsDevice:device_]) {
      MTLFXSpatialScalerDescriptor *d=[MTLFXSpatialScalerDescriptor new];
      d.inputWidth=width_;d.inputHeight=height_;d.outputWidth=outputWidth;d.outputHeight=outputHeight;
      d.colorTextureFormat=format_;d.outputTextureFormat=MTLPixelFormatBGRA8Unorm;
      d.colorProcessingMode=MTLFXSpatialScalerColorProcessingModePerceptual;
      spatial_=[d newSpatialScalerWithDevice:device_];
    }
    if(!spatial_ && MPSSupportsMTLDevice(device_)) {
      bilinear_=[[MPSImageBilinearScale alloc] initWithDevice:device_];
      bilinear_.edgeMode=MPSImageEdgeModeClamp;
    }
  }
  if(!spatial_ && !bilinear_)return nil;
  slot%=outputs_.size();
  if(!outputs_[slot]) {
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
      width:outputWidth height:outputHeight mipmapped:NO];
    d.storageMode=MTLStorageModePrivate;
    d.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|(spatial_ ? spatial_.outputTextureUsage : 0);
    outputs_[slot]=[device_ newTextureWithDescriptor:d];
    outputs_[slot].label=@"Game presentation output";
  }
  id<MTLTexture> output=outputs_[slot];
  if(!output)return nil;
  id<MTLTexture> input=color;
  MTLTextureUsage required=spatial_ ? spatial_.colorTextureUsage : MTLTextureUsageShaderRead;
  if((color.usage&required)!=required) {
      if(!inputs_[slot]) {
        MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format_
          width:width_ height:height_ mipmapped:NO];
        d.storageMode=MTLStorageModePrivate;d.usage=required|MTLTextureUsageShaderRead;
        inputs_[slot]=[device_ newTextureWithDescriptor:d];
      }
      input=inputs_[slot];if(!input)return nil;
      id<MTLBlitCommandEncoder> e=[cb blitCommandEncoder];
      [e copyFromTexture:color sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
        sourceSize:MTLSizeMake(width_,height_,1) toTexture:input destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
      [e endEncoding];
  }
  if(spatial_) {
    spatial_.colorTexture=input;spatial_.inputContentWidth=width_;spatial_.inputContentHeight=height_;
    spatial_.outputTexture=output;
    [spatial_ encodeToCommandBuffer:cb];usedMetalFX_=true;
  } else {
    MPSScaleTransform transform={(double)outputWidth/width_,(double)outputHeight/height_,0,0};
    bilinear_.scaleTransform=&transform;
    [bilinear_ encodeToCommandBuffer:cb sourceTexture:input destinationTexture:output];
    bilinear_.scaleTransform=nullptr;
  }
  return output;
}
}
