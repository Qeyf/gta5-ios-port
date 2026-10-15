#include "NativeEngineConfiguration.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
 for(unsigned hardware=0;hardware<=16;hardware++)
  assert(pg_engine_core_configuration(NULL,hardware)==(hardware>=6?4:2));
 assert(pg_engine_core_configuration(NULL,2)==2);
 assert(pg_engine_core_configuration("invalid",6)==4);
 assert(pg_engine_core_configuration("2",6)==2);
 assert(pg_engine_core_configuration("4",2)==4);
 assert(pg_engine_core_configuration("",2)==2);
 assert(pg_engine_core_configuration("0",2)==2);
 assert(pg_engine_core_configuration("-1",2)==2);
 assert(pg_engine_core_configuration("9",2)==2);
 assert(pg_engine_core_configuration("3junk",2)==2);
 assert(pg_engine_core_configuration("invalid",2)==2);
 assert(pg_engine_core_configuration("999999999999999999999999999999999",2)==2);
 for(unsigned i=1;i<=8;i++){char text[4];snprintf(text,sizeof text,"%u",i);assert(pg_engine_core_configuration(text,2)==i);}
 puts("PASS: native worker configuration defaults, valid values, bounds, trailing text, and overflow");
 return 0;
}
