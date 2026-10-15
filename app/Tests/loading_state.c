#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
#include "NativeTouchContext.h"

int main(void) {
  const size_t size = 19473640;
  uint8_t *memory = calloc(1, size);
  assert(memory);
  assert(pg_loading_screen_active(NULL, size));
  assert(pg_loading_screen_active(memory, 0));
  assert(pg_loading_screen_active(memory, size-1));
  assert(!pg_loading_screen_active(memory, size));
  atomic_store((_Atomic uint32_t *)(memory+19473636), 2);
  assert(pg_loading_screen_active(memory, size));
  assert(atomic_load((_Atomic uint32_t *)(memory+19473636)) == 2);
  atomic_store((_Atomic uint32_t *)(memory+19473636), 0);
  memory[6972816] = 1;
  assert(pg_loading_screen_active(memory, size));
  memory[6972816] = 0;
  assert(!pg_loading_screen_active(memory, size));
  free(memory);
  puts("PASS: production loading-screen snapshot is read-only and fails closed before memory is ready.");
  return 0;
}
