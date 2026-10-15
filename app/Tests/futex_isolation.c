// Force preemption immediately after one engine wait-queue lock is acquired.
// A notification for an unrelated address must still make progress. Exercise
// the real runtime/pthreads; interception adds scheduling, not a fake result.
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include "WasmFutex.h"

static _Thread_local bool suspendAfterLock;
static _Atomic bool held, releaseFirst, secondFinished;
static wasm_rt_shared_memory_t memory;

static double seconds(void) {
  struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t);
  return t.tv_sec + t.tv_nsec/1e9;
}
static void pauseBriefly(void) { struct timespec t={0,1000000};nanosleep(&t,NULL); }
static bool await(_Atomic bool *flag) {
  double deadline=seconds()+2;
  while(!atomic_load(flag) && seconds()<deadline)pauseBriefly();
  return atomic_load(flag);
}
static int preemptingLock(pthread_mutex_t *mutex) {
  int result=pthread_mutex_lock(mutex);
  if(!result && suspendAfterLock) {
    suspendAfterLock=false;atomic_store(&held,true);
    while(!atomic_load(&releaseFirst))pauseBriefly();
  }
  return result;
}

#define pthread_mutex_lock preemptingLock
#include "../Source/WasmFutex.c"
#undef pthread_mutex_lock

void wasm_rt_trap(wasm_rt_trap_t code) { fprintf(stderr,"Unexpected trap %d\n",code);abort(); }
static void *first(void *unused) {
  suspendAfterLock=true;
  assert(pg_atomic_notify(&memory,0,1)==0);return NULL;
}
static void *second(void *unused) {
  assert(pg_atomic_notify(&memory,4,1)==0);
  atomic_store(&secondFinished,true);return NULL;
}
int main(void) {
  alarm(10);
  memory.data=calloc(1,64);memory.size=64;assert(memory.data);
  pthread_t a,b;
  assert(!pthread_create(&a,NULL,first,NULL));assert(await(&held));
  assert(!pthread_create(&b,NULL,second,NULL));
  bool independent=await(&secondFinished);
  atomic_store(&releaseFirst,true);
  pthread_join(a,NULL);pthread_join(b,NULL);
  assert(independent && "An unrelated address waited for a preempted engine worker");
  free((void*)memory.data);
  puts("PASS: an unrelated futex notification progresses while another address's queue is preempted.");
}
