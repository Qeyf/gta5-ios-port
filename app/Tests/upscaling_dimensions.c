#include "NativeUpscaling.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
  PGRenderDimensions d = pg_render_dimensions(2346,1080,1,true);
  assert(d.outputWidth==2346 && d.outputHeight==1080);
  assert(d.width==1564 && d.height==720 && d.upscaled);
  d=pg_render_dimensions(2346,1080,2,true);
  assert(d.width==1172 && d.height==540 && d.upscaled);
  d=pg_render_dimensions(2868,1320,1,true);
  assert(d.width==1912 && d.height==880);
  for(int mode=0;mode<=3;mode++) {
    d=pg_render_dimensions(2346,1080,mode,false);
    assert(d.width==2346 && d.height==1080 && !d.upscaled);
  }
  d=pg_render_dimensions(2346,1080,0,true);
  assert(d.width==2346 && d.height==1080 && !d.upscaled);
  d=pg_render_dimensions(2346,1080,99,true);
  assert(d.width==2346 && d.height==1080 && !d.upscaled);
  d=pg_render_dimensions(320,180,2,true);
  assert(d.width==320 && d.height==180 && !d.upscaled);
  d=pg_render_dimensions(-1,0,1,true);
  assert(d.outputWidth==320 && d.outputHeight==180 && !d.upscaled);
  d=pg_render_dimensions(9000,9000,1,true);
  assert(d.outputWidth==3840 && d.outputHeight==2160);
  assert(d.width==2560 && d.height==1440);
  for(int h=360;h<=2160;h+=2)for(int mode=1;mode<=2;mode++) {
    d=pg_render_dimensions(h*2,h,mode,true);
    assert(d.width>=320 && d.height>=180 && !(d.width&1) && !(d.height&1));
    assert(d.width<=d.outputWidth && d.height<=d.outputHeight);
    if(d.upscaled) {
      double ratio=(double)d.width*d.height/(d.outputWidth*d.outputHeight);
      assert(ratio<=(mode==1 ? 0.445 : 0.251));
    }
  }
  puts("PASS: native/MetalFX input-output dimensions, unsupported fallback, engine bounds and reduced pixel work.");
}
