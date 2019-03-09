#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define WASM_RT_MODULE_PREFIX waforth_core_
#include "waforth_core.h"
#undef WASM_RT_MODULE_PREFIX
#include "waforth.gen/waforth_modules.h"

void (*Z_shellZ_emitZ_vi)(u32);
u32 (*Z_shellZ_keyZ_iv)(void);
void (*Z_shellZ_loadZ_viii)(u32, u32, u32);
void (*Z_shellZ_debugZ_vi)(u32);
wasm_rt_table_t (*Z_envZ_table);
wasm_rt_memory_t (*Z_envZ_memory);

static void shellEmit(u32 c) {
  printf("%c", c);
  fflush(stdout);
}

static int bufferIndex;
char* buffer = "main\n";

static u32 shellKey() {
  if (bufferIndex >= strlen(buffer)) {
    return -1;
  }
  return buffer[bufferIndex++];
}

static void shellLoad(u32 offset, u32 length, u32 index) {
  printf("Loading not supported!\n");
}

static void shellDebug(u32 c) {
  fprintf(stderr, "%d\n", c);
}

void wasm_rt_reallocate_table(wasm_rt_table_t* table, uint32_t elements, uint32_t max_elements) {
  table->size = elements;
  table->max_size = max_elements;
  table->data = realloc(table->data, table->size * sizeof(wasm_rt_elem_t));
}

void waforth_init() {
  waforth_core_init();

  if (WAFORTH_TABLE_SIZE >= 0) {
    wasm_rt_reallocate_table(waforth_core_Z_table, WAFORTH_TABLE_SIZE, waforth_core_Z_table->max_size);
  }

  Z_shellZ_emitZ_vi = &shellEmit;
  Z_shellZ_keyZ_iv = &shellKey;
  Z_shellZ_loadZ_viii = &shellLoad;
  Z_shellZ_debugZ_vi = &shellDebug;

  Z_envZ_table = waforth_core_Z_table;
  Z_envZ_memory = waforth_core_Z_memory;

  waforth_core_Z_set_stateZ_vii(WAFORTH_LATEST, WAFORTH_HERE);

  waforth_modules_init();

  bufferIndex = 0;
  waforth_core_Z_interpretZ_iv();
}
