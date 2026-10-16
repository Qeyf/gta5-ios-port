#include "NativePipelineWarmup.h"
#include <cassert>
#include <cstdio>

int main() {
    PGPipelineWarmupQueue q;
    size_t index=99;
    q.reset(3);
    assert(q.next(1,index) && index==0);
    q.defer(index); // Vertex signature has not arrived.
    assert(q.next(1,index) && index==1);
    assert(q.next(1,index) && index==2);
    assert(!q.next(1,index));
    for(int i=0;i<10000;i++)assert(!q.next(1,index));
    assert(q.next(2,index) && index==0); // New engine shader makes one retry possible.
    q.defer(index);
    assert(!q.next(2,index));
    assert(q.next(3,index) && index==0);
    assert(!q.next(3,index)); // Successfully consumed: no more retries.

    q.reset(2);
    assert(q.next(7,index) && index==0);
    q.defer(index);
    q.stop(); // World rendering/thermal pressure: no further startup work.
    assert(!q.next(8,index));
    q.reset(0);
    assert(!q.next(9,index));

    // Signatures arriving mid-pass must be visible to deferred work, without
    // skipping the recipes that have not yet been inspected in that pass.
    q.reset(3);
    assert(q.next(10,index) && index==0);q.defer(index);
    assert(q.next(11,index) && index==1);q.defer(index);
    assert(q.next(11,index) && index==2);
    assert(q.next(11,index) && index==0);
    assert(q.next(11,index) && index==1);q.defer(index);
    assert(!q.next(11,index));
    assert(q.next(12,index) && index==1);
    assert(!q.next(12,index));
    puts("PASS: startup pipeline recipes wait for engine signatures, retry once per generation and stop for gameplay/pressure.");
}
