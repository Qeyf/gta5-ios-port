#include <assert.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>

#if __has_include("NativeCheatInput.h")
#include "NativeCheatInput.h"

static _Alignas(8) uint8_t memory[512];
static const uint64_t block = 32;

static void console_delivers_text_and_key_edges(void) {
  PGCheatSequence sequence;
  assert(pg_cheat_console_sequence(&sequence, "AB"));
  assert(sequence.console && sequence.count == 10);
  const uint32_t delays[] = {120,80,300,60,40,60,40,100,80,400};
  for (unsigned i = 0; i < sequence.count; i++) assert(sequence.steps[i].delayMS == delays[i]);
  memset(memory, 0, sizeof memory);
  for (unsigned i = 0; i < sequence.count; i++) {
    const PGCheatStep *step = &sequence.steps[i];
    if (step->kind != PG_CHEAT_KEY) continue;
    assert(pg_cheat_key_step(memory, sizeof memory, block, step));
    assert(memory[block + step->key] == (step->down ? 0x80 : 0));
  }
  uint16_t expected[] = {'`','A','B',13};
  assert(atomic_load((_Atomic uint32_t *)(memory+block+288)) == 4);
  for (unsigned i = 0; i < 4; i++)
    assert(atomic_load((_Atomic uint16_t *)(memory+block+296+2*i)) == expected[i]);
  for (unsigned i = 0; i < 256; i++) assert(memory[block+i] == 0);
}

static void full_or_malformed_ring_never_overwrites_or_holds_a_key(void) {
  PGCheatSequence sequence;
  assert(pg_cheat_console_sequence(&sequence, "A"));
  const PGCheatStep *letter = &sequence.steps[3];
  memset(memory, 0x5a, sizeof memory);
  atomic_store((_Atomic uint32_t *)(memory+block+288), 64);
  atomic_store((_Atomic uint32_t *)(memory+block+292), 0);
  uint8_t before[sizeof memory]; memcpy(before, memory, sizeof before);
  assert(!pg_cheat_key_step(memory, sizeof memory, block, letter));
  assert(memcmp(before, memory, sizeof memory) == 0);
  atomic_store((_Atomic uint32_t *)(memory+block+288), 0);
  atomic_store((_Atomic uint32_t *)(memory+block+292), 1);
  memcpy(before, memory, sizeof before);
  assert(!pg_cheat_key_step(memory, sizeof memory, block, letter));
  assert(memcmp(before, memory, sizeof memory) == 0);
  assert(!pg_cheat_key_step(memory, block+443, block, letter));
  assert(!pg_cheat_key_step(memory, sizeof memory, UINT64_MAX, letter));
  assert(!pg_cheat_key_step(memory, sizeof memory, block+1, letter));
  assert(memcmp(before, memory, sizeof memory) == 0);
}

static void ring_wrap_uses_the_next_free_slot(void) {
  PGCheatSequence sequence;
  assert(pg_cheat_console_sequence(&sequence, "A"));
  memset(memory, 0, sizeof memory);
  atomic_store((_Atomic uint32_t *)(memory+block+288), UINT32_MAX);
  atomic_store((_Atomic uint32_t *)(memory+block+292), UINT32_MAX-63);
  assert(pg_cheat_key_step(memory, sizeof memory, block, &sequence.steps[3]));
  assert(atomic_load((_Atomic uint32_t *)(memory+block+288)) == 0);
  assert(atomic_load((_Atomic uint16_t *)(memory+block+296+126)) == 'A');
}

static void gamepad_has_distinct_edges_and_full_analog_triggers(void) {
  const uint16_t buttons[] = {64, 64, 1, 2, 32768};
  PGCheatSequence sequence;
  assert(pg_cheat_gamepad_sequence(&sequence, buttons, 5));
  assert(!sequence.console && sequence.count == 12);
  assert(sequence.steps[0].kind == PG_CHEAT_PAD && sequence.steps[0].buttons == 0);
  assert(sequence.steps[0].delayMS == 100);
  for (unsigned i = 0; i < 5; i++) {
    assert(sequence.steps[2*i+1].buttons == buttons[i]);
    assert(sequence.steps[2*i+1].delayMS == 90);
    assert(sequence.steps[2*i+2].buttons == 0);
    assert(sequence.steps[2*i+2].delayMS == 60);
  }
  assert(sequence.steps[11].kind == PG_CHEAT_WAIT && sequence.steps[11].delayMS == 400);
  assert(pg_cheat_pad_sample(1) == (PG_CHEAT_NEUTRAL_PAD | 1ull | 0xffull<<48));
  assert(pg_cheat_pad_sample(2) == (PG_CHEAT_NEUTRAL_PAD | 2ull | 0xffull<<56));
}

static void cancelling_any_sequence_prefix_releases_input(void) {
  PGCheatSequence sequence;
  assert(pg_cheat_console_sequence(&sequence, "AB"));
  for (unsigned prefix = 0; prefix <= sequence.count; prefix++) {
    memset(memory, 0, sizeof memory);
    _Atomic uint64_t pad = pg_cheat_pad_sample(64);
    for (unsigned i = 0; i < prefix; i++)
      if (sequence.steps[i].kind == PG_CHEAT_KEY)
        assert(pg_cheat_key_step(memory, sizeof memory, block, &sequence.steps[i]));
    for (unsigned offset = 264; offset <= 276; offset += 4)
      atomic_store((_Atomic uint32_t *)(memory+block+offset), 42);
    assert(pg_cheat_release_input(memory, sizeof memory, block, &pad));
    assert(atomic_load(&pad) == PG_CHEAT_NEUTRAL_PAD);
    for (unsigned i = 0; i < 256; i++) assert(memory[block+i] == 0);
    for (unsigned offset = 264; offset <= 276; offset += 4)
      assert(atomic_load((_Atomic uint32_t *)(memory+block+offset)) == 0);
  }
  memset(memory, 0x5a, sizeof memory);
  uint8_t before[sizeof memory]; memcpy(before, memory, sizeof before);
  _Atomic uint64_t pad = pg_cheat_pad_sample(2);
  assert(!pg_cheat_release_input(memory, block+443, block, &pad));
  assert(atomic_load(&pad) == PG_CHEAT_NEUTRAL_PAD);
  assert(memcmp(before, memory, sizeof memory) == 0);
}

static void invalid_requests_cannot_build_sequences(void) {
  PGCheatSequence sequence;
  assert(!pg_cheat_console_sequence(&sequence, NULL));
  assert(!pg_cheat_console_sequence(&sequence, ""));
  assert(!pg_cheat_console_sequence(&sequence, "A;B"));
  assert(!pg_cheat_console_sequence(&sequence, "A\n"));
  assert(!pg_cheat_console_sequence(&sequence, "a"));
  assert(!pg_cheat_console_sequence(&sequence, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"));
  assert(pg_cheat_console_sequence(&sequence, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"));
  uint16_t good[32]; for (unsigned i = 0; i < 32; i++) good[i] = 64;
  assert(pg_cheat_gamepad_sequence(&sequence, good, 32));
  assert(!pg_cheat_gamepad_sequence(&sequence, good, 33));
  assert(!pg_cheat_gamepad_sequence(&sequence, good, 0));
  assert(!pg_cheat_gamepad_sequence(&sequence, NULL, 1));
  const uint16_t invalid[] = {0,3,256,512,1024,2048};
  for (unsigned i = 0; i < sizeof invalid / sizeof *invalid; i++)
    assert(!pg_cheat_gamepad_sequence(&sequence, invalid+i, 1));
}

static void ownership_is_reserved_before_launch_and_cancel_wins_completion(void) {
#ifdef PG_CHEAT_OWNERSHIP
  _Atomic int32_t state = 0;
  assert(pg_cheat_claim(&state));
  assert(pg_cheat_busy(&state) && pg_cheat_result(&state) == 1);
  assert(!pg_cheat_claim(&state));
  pg_cheat_cancel(&state);
  assert(pg_cheat_busy(&state) && pg_cheat_result(&state) == 1);
  pg_cheat_finish(&state, 2);
  assert(!pg_cheat_busy(&state) && pg_cheat_result(&state) == 3);
  pg_cheat_cancel(&state);
  assert(pg_cheat_result(&state) == 3);
  assert(pg_cheat_claim(&state));
  pg_cheat_finish(&state, 4); // Allocation/thread failure after reservation.
  assert(!pg_cheat_busy(&state) && pg_cheat_result(&state) == 4);
  assert(pg_cheat_claim(&state));
  pg_cheat_finish(&state, 2);
  assert(pg_cheat_result(&state) == 2);
#else
  assert(!"Cheat ownership is not implemented");
#endif
}

#ifdef PG_CHEAT_OWNERSHIP
static _Atomic int32_t competingState;
static _Atomic unsigned winners;
static void *competing_request(void *unused) {
  (void)unused;
  if (pg_cheat_claim(&competingState)) atomic_fetch_add(&winners, 1);
  return NULL;
}
static void concurrent_requests_have_one_owner(void) {
  pthread_t threads[16];
  for (unsigned i = 0; i < 16; i++) assert(pthread_create(threads+i, NULL, competing_request, NULL) == 0);
  for (unsigned i = 0; i < 16; i++) assert(pthread_join(threads[i], NULL) == 0);
  assert(atomic_load(&winners) == 1);
  pg_cheat_cancel(&competingState);
  pg_cheat_finish(&competingState, 2);
  assert(pg_cheat_result(&competingState) == 3);
}
#endif

int main(void) {
  console_delivers_text_and_key_edges();
  full_or_malformed_ring_never_overwrites_or_holds_a_key();
  ring_wrap_uses_the_next_free_slot();
  gamepad_has_distinct_edges_and_full_analog_triggers();
  cancelling_any_sequence_prefix_releases_input();
  invalid_requests_cannot_build_sequences();
  ownership_is_reserved_before_launch_and_cancel_wins_completion();
#ifdef PG_CHEAT_OWNERSHIP
  concurrent_requests_have_one_owner();
#endif
  puts("Cheat input: key/text delivery, bounded and wrapped ring, pad edges/triggers, cancel cleanup and validation passed.");
}
#else
int main(void) {
  fputs("FAIL: NativeCheatInput sequence and safe input delivery are not implemented.\n", stderr);
  return 1;
}
#endif
