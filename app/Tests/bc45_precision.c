#include "../Source/BCTextureDecoder.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// Independent nearest-UNorm palette oracle for unsigned endpoint modes.
static unsigned expected(unsigned a,unsigned b,unsigned selector) {
    if(selector<2)return selector ? b : a;
    if(a>b)return ((8-selector)*a+(selector-1)*b+3)/7;
    if(selector>=6)return selector==6 ? 0 : 255;
    return ((6-selector)*a+(selector-1)*b+2)/5;
}

int main(void) {
    // Exact block from the failing 8x8 copy. Full-image pixel(2,1) is block
    // pixel6: ideal90.8, nearest91, whereas the legacy decoder truncated to90.
    const uint8_t reported[]={0x02,0xe0,0x8a,0x20,0x2f,0x4e,0xbc,0x14};
    size_t bytes=0;
    uint8_t *pixels=PGDecodeBC(4,4,4,1,0,0,reported,sizeof reported,&bytes);
    assert(pixels && bytes==16 && pixels[6]==91);
    free(pixels);
    pixels=PGDecodeBC(4,3,2,1,0,0,reported,sizeof reported,&bytes);
    assert(pixels && bytes==6 && pixels[5]==91); // Clipped block uses same mode.
    free(pixels);

    uint64_t selectors=0;
    for(unsigned i=0;i<16;i++)selectors|=(uint64_t)(i%8)<<(3*i);
    for(unsigned a=0;a<256;a++)for(unsigned b=0;b<256;b++) {
        uint8_t block[16]={0};block[0]=(uint8_t)a;block[1]=(uint8_t)b;
        block[8]=(uint8_t)b;block[9]=(uint8_t)a;
        for(unsigned i=0;i<6;i++)block[2+i]=block[10+i]=(uint8_t)(selectors>>(8*i));
        for(int kind=4;kind<=5;kind++) {
            unsigned components=kind==4 ? 1 : 2;
            pixels=PGDecodeBC(kind,4,4,1,0,0,block,components*8,&bytes);
            assert(pixels && bytes==16*components);
            for(unsigned i=0;i<16;i++) {
                assert(pixels[i*components]==expected(a,b,i%8));
                if(components==2)assert(pixels[i*2+1]==expected(b,a,i%8));
            }
            free(pixels);
        }
    }
    puts("PASS: actual BC4/BC5 decoder nearest-UNorm precision for all 65536 endpoint pairs, both palette modes, all selectors, two channels and reported/clipped block.");
}
