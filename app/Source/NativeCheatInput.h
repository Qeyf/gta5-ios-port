#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>
#include <string.h>

// Timings and the UTF-16 input ring match the reference port's real input
// bridge. These helpers have no engine, UIKit, thread, or wall-clock dependency.
#define PG_CHEAT_MAX_CODE 32u
#define PG_CHEAT_MAX_BUTTONS 32u
#define PG_CHEAT_MAX_STEPS (2u * PG_CHEAT_MAX_CODE + 6u)
#define PG_CHEAT_NEUTRAL_PAD UINT64_C(0x0000808080800000)
#define PG_CHEAT_OWNERSHIP 1

// Internal state 5 keeps ownership until a cancellation has cleaned up. The
// public result stays "sending" until every held input has been released.
static inline bool pg_cheat_busy(const _Atomic int32_t *state) {
  int32_t value = atomic_load(state);
  return value == 1 || value == 5;
}
static inline int32_t pg_cheat_result(const _Atomic int32_t *state) {
  int32_t value = atomic_load(state);
  return value == 5 ? 1 : value;
}
static inline bool pg_cheat_claim(_Atomic int32_t *state) {
  int32_t value = atomic_load(state);
  do {
    if (value == 1 || value == 5) return false;
  } while (!atomic_compare_exchange_weak(state, &value, 1));
  return true;
}
static inline void pg_cheat_cancel(_Atomic int32_t *state) {
  int32_t expected = 1;
  atomic_compare_exchange_strong(state, &expected, 5);
}
static inline void pg_cheat_finish(_Atomic int32_t *state, int32_t result) {
  int32_t value = atomic_load(state);
  do {
    if (value != 1 && value != 5) return;
  } while (!atomic_compare_exchange_weak(state, &value, value == 5 ? 3 : result));
}

typedef enum { PG_CHEAT_WAIT, PG_CHEAT_KEY, PG_CHEAT_PAD } PGCheatStepKind;
typedef struct {
  PGCheatStepKind kind;
  uint8_t key;
  bool down;
  uint16_t text, buttons;
  uint32_t delayMS;
} PGCheatStep;
typedef struct {
  bool console;
  unsigned count;
  PGCheatStep steps[PG_CHEAT_MAX_STEPS];
} PGCheatSequence;

static inline bool pg_cheat_console_sequence(PGCheatSequence *sequence, const char *code) {
  if (!sequence || !code) return false;
  unsigned length = 0;
  while (length <= PG_CHEAT_MAX_CODE && code[length]) {
    if (code[length] < 'A' || code[length] > 'Z') return false;
    length++;
  }
  if (!length || length > PG_CHEAT_MAX_CODE) return false;
  *sequence = (PGCheatSequence){ .console = true };
  sequence->steps[sequence->count++] = (PGCheatStep){ .delayMS = 120 };
  sequence->steps[sequence->count++] = (PGCheatStep){ PG_CHEAT_KEY, 0xc0, true, '`', 0, 80 };
  sequence->steps[sequence->count++] = (PGCheatStep){ PG_CHEAT_KEY, 0xc0, false, 0, 0, 300 };
  for (unsigned i = 0; i < length; i++) {
    sequence->steps[sequence->count++] = (PGCheatStep){ PG_CHEAT_KEY, (uint8_t)code[i], true, (uint16_t)code[i], 0, 60 };
    sequence->steps[sequence->count++] = (PGCheatStep){ PG_CHEAT_KEY, (uint8_t)code[i], false, 0, 0, 40 };
  }
  sequence->steps[sequence->count++] = (PGCheatStep){ .delayMS = 100 };
  sequence->steps[sequence->count++] = (PGCheatStep){ PG_CHEAT_KEY, 13, true, 13, 0, 80 };
  sequence->steps[sequence->count++] = (PGCheatStep){ PG_CHEAT_KEY, 13, false, 0, 0, 400 };
  return true;
}

static inline bool pg_cheat_gamepad_sequence(PGCheatSequence *sequence, const uint16_t *buttons, unsigned count) {
  if (!sequence || !buttons || !count || count > PG_CHEAT_MAX_BUTTONS) return false;
  // Face buttons, shoulders, triggers, D-pad; never Menu/Back/stick clicks.
  for (unsigned i = 0; i < count; i++)
    if (!buttons[i] || (buttons[i] & (buttons[i]-1)) || (buttons[i] & ~UINT16_C(0xf0ff))) return false;
  *sequence = (PGCheatSequence){0};
  sequence->steps[sequence->count++] = (PGCheatStep){ .kind = PG_CHEAT_PAD, .delayMS = 100 };
  for (unsigned i = 0; i < count; i++) {
    sequence->steps[sequence->count++] = (PGCheatStep){ .kind = PG_CHEAT_PAD, .buttons = buttons[i], .delayMS = 90 };
    sequence->steps[sequence->count++] = (PGCheatStep){ .kind = PG_CHEAT_PAD, .delayMS = 60 };
  }
  sequence->steps[sequence->count++] = (PGCheatStep){ .delayMS = 400 };
  return true;
}

static inline uint64_t pg_cheat_pad_sample(uint16_t buttons) {
  return PG_CHEAT_NEUTRAL_PAD | buttons |
    (buttons & 1 ? UINT64_C(0xff) << 48 : 0) |
    (buttons & 2 ? UINT64_C(0xff) << 56 : 0);
}

static inline bool pg_cheat_input_bounds(const uint8_t *memory, uint64_t size, uint64_t block) {
  // The published block is 0x64748c. Its widest atomic fields are uint32_t,
  // so four-byte alignment is required; eight-byte alignment rejects it.
  return memory && block && !(block & 3) && block <= size && size-block >= 444;
}

static inline bool pg_cheat_key_step(uint8_t *memory, uint64_t size, uint64_t block, const PGCheatStep *step) {
  if (!step || step->kind != PG_CHEAT_KEY || !pg_cheat_input_bounds(memory, size, block)) return false;
  uint8_t *input = memory + block;
  if (step->text) {
    _Atomic uint32_t *head = (_Atomic uint32_t *)(input + 288);
    const _Atomic uint32_t *tail = (const _Atomic uint32_t *)(input + 292);
    uint32_t write = atomic_load(head), read = atomic_load(tail);
    // Unsigned subtraction handles wrapping counters and rejects corrupt ones.
    if (write-read >= 64) return false;
    atomic_store_explicit((_Atomic uint16_t *)(input+296+2u*(write & 63)), step->text, memory_order_relaxed);
    atomic_store_explicit(head, write+1, memory_order_release);
  }
  atomic_store((_Atomic uint8_t *)(input+step->key), step->down ? 0x80 : 0);
  return true;
}

static inline bool pg_cheat_release_input(uint8_t *memory, uint64_t size, uint64_t block, _Atomic uint64_t *pad) {
  if (pad) atomic_store(pad, PG_CHEAT_NEUTRAL_PAD);
  if (!pg_cheat_input_bounds(memory, size, block)) return false;
  uint8_t *input = memory + block;
  for (unsigned i = 0; i < 256; i++) atomic_store((_Atomic uint8_t *)(input+i), 0);
  for (unsigned offset = 264; offset <= 276; offset += 4)
    atomic_store((_Atomic uint32_t *)(input+offset), 0);
  return true;
}
