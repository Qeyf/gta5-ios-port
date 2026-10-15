#pragma once
#include <stdint.h>
#include <stdbool.h>
int32_t PGUISmokeMouseButtons(void);
int32_t PGUISmokeMouseDX(void);
int32_t PGUISmokeMouseDY(void);
int32_t PGUISmokeMouseWheel(void);
bool PGUISmokeKeyDown(uint8_t key);
void PGUISmokeRuntimeState(uint32_t status,bool loading);
int32_t PGUISmokeFrameLimit(void);
