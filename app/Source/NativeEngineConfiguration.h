#pragma once
#include <stdlib.h>
#include <errno.h>

// A budget for the engine's several independent pools, not the hardware count.
// C=2 serializes dependency/gtaSched/cloth onto one worker each; C=4 gives two.
// Advertising all six iPhone cores would expand these six pools from 8 to 26
// workers. Bound that expansion to 16 on >=6 active CPUs. Device profiling is
// still required; a higher budget is not a guarantee of higher frame rates.
static inline unsigned pg_engine_core_configuration(const char *text,unsigned activeCores) {
 unsigned fallback=activeCores>=6?4:2;
 if(!text||!*text)return fallback;
 char *end;errno=0;long value=strtol(text,&end,10);
 if(errno||end==text||*end||value<1||value>8)return fallback;
 return (unsigned)value;
}
