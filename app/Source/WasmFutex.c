#include "WasmFutex.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <errno.h>
#include <time.h>

// Instances sharing the same backing address use the same wait queue.
// Unrelated engine/render/audio addresses need not serialize on one mutex.
// Per-waiter condition variables preserve exact-count notification semantics.
typedef struct Waiter {
  const void *address;
  bool notified;
  pthread_cond_t condition;
  struct Waiter *next;
} Waiter;

typedef struct WaitQueue {
  _Alignas(128) pthread_mutex_t lock;
  Waiter *waiters;
} WaitQueue;
enum { WAIT_QUEUE_COUNT = 64 };
static WaitQueue queues[WAIT_QUEUE_COUNT];
static pthread_once_t queuesOnce = PTHREAD_ONCE_INIT;
static void initializeQueues(void) {
  for(unsigned i=0;i<WAIT_QUEUE_COUNT;i++)pthread_mutex_init(&queues[i].lock,NULL);
}
static WaitQueue *queueFor(const void *address) {
  pthread_once(&queuesOnce,initializeQueues);
  uintptr_t key=(uintptr_t)address>>2;
  key^=key>>9;key^=key>>17;
  return &queues[key & (WAIT_QUEUE_COUNT-1)];
}

static void *checkedAddress(wasm_rt_shared_memory_t *memory, uint64_t offset,
                            uint32_t width) {
  if (offset % width) wasm_rt_trap(WASM_RT_TRAP_UNALIGNED);
  if (offset > memory->size || memory->size - offset < width)
    wasm_rt_trap(WASM_RT_TRAP_OOB);
  return (uint8_t *)(void *)memory->data + offset;
}

static uint32_t waitFor(wasm_rt_shared_memory_t *memory, uint64_t offset,
                        uint64_t expected, uint64_t timeoutBits, uint32_t width) {
  void *address = checkedAddress(memory, offset, width);
  WaitQueue *queue=queueFor(address);
  pthread_mutex_lock(&queue->lock);
  uint64_t value = width == 4 ? atomic_load((_Atomic uint32_t *)address)
                              : atomic_load((_Atomic uint64_t *)address);
  if (value != expected) {
    pthread_mutex_unlock(&queue->lock);
    return 1;
  }
  int64_t timeout = (int64_t)timeoutBits;
  if (!timeout) {
    pthread_mutex_unlock(&queue->lock);
    return 2;
  }
  Waiter waiter = {.address = address, .notified = false, .next = queue->waiters};
  pthread_cond_init(&waiter.condition, NULL);
  queue->waiters = &waiter;
  struct timespec deadline;
  if (timeout > 0) {
    clock_gettime(CLOCK_MONOTONIC, &deadline);
    deadline.tv_sec += timeout / 1000000000;
    deadline.tv_nsec += timeout % 1000000000;
    if (deadline.tv_nsec >= 1000000000) {
      deadline.tv_sec++;
      deadline.tv_nsec -= 1000000000;
    }
  }
  int result = 0;
  while (!waiter.notified && !result) {
    if (timeout < 0) {
      result = pthread_cond_wait(&waiter.condition, &queue->lock);
    } else {
      // Apple's relative wait uses monotonic time, so wall-clock changes cannot
      // extend or shorten an engine sleep. Recalculate after a spurious wakeup.
      struct timespec now, remaining;
      clock_gettime(CLOCK_MONOTONIC, &now);
      remaining.tv_sec = deadline.tv_sec - now.tv_sec;
      remaining.tv_nsec = deadline.tv_nsec - now.tv_nsec;
      if (remaining.tv_nsec < 0) { remaining.tv_sec--; remaining.tv_nsec += 1000000000; }
      if (remaining.tv_sec < 0) result = ETIMEDOUT;
      else result = pthread_cond_timedwait_relative_np(&waiter.condition, &queue->lock, &remaining);
    }
  }
  Waiter **link = &queue->waiters;
  while (*link != &waiter) link = &(*link)->next;
  *link = waiter.next;
  bool notified = waiter.notified;
  pthread_mutex_unlock(&queue->lock);
  pthread_cond_destroy(&waiter.condition);
  return notified ? 0 : 2;
}

uint32_t pg_atomic_wait32(wasm_rt_shared_memory_t *m, uint64_t a, uint32_t v,
                           uint64_t timeout) { return waitFor(m, a, v, timeout, 4); }
uint32_t pg_atomic_wait64(wasm_rt_shared_memory_t *m, uint64_t a, uint64_t v,
                           uint64_t timeout) { return waitFor(m, a, v, timeout, 8); }

uint32_t pg_atomic_notify(wasm_rt_shared_memory_t *m, uint64_t offset,
                           uint32_t count) {
  void *address = checkedAddress(m, offset, 4);
  WaitQueue *queue=queueFor(address);
  uint32_t total = 0;
  pthread_mutex_lock(&queue->lock);
  for (Waiter *w = queue->waiters; w && total < count; w = w->next) {
    if (w->address == address && !w->notified) {
      w->notified = true;
      pthread_cond_signal(&w->condition);
      total++;
    }
  }
  pthread_mutex_unlock(&queue->lock);
  return total;
}
