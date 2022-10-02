#include <stdio.h>
#include <termios.h>

#include "waforth_core.h"
#include "wasm.h"

#ifndef VERSION
#define VERSION "dev"
#endif

#define CORE_RUN_EXPORT_INDEX 0
#define CORE_TABLE_EXPORT_INDEX 1
#define CORE_MEMORY_EXPORT_INDEX 2
#define CORE_ERROR_EXPORT_INDEX 9

#define ERR_UNKNOWN 0x1
#define ERR_QUIT 0x2
#define ERR_ABORT 0x3
#define ERR_EOI 0x4
#define ERR_BYE 0x5

wasm_memory_t *memory;
wasm_table_t *table;
wasm_store_t *store;

////////////////////////////////////////////////////////////////////////////////
// Utility
////////////////////////////////////////////////////////////////////////////////

wasm_trap_t *trap_from_string(const char *s) {
  wasm_name_t message;
  wasm_name_new_from_string_nt(&message, s);
  wasm_trap_t *trap = wasm_trap_new(store, &message);
  wasm_name_delete(&message);
  return trap;
}

void print_trap(wasm_trap_t *trap) {
  wasm_name_t message;
  wasm_trap_message(trap, &message);
  printf(">> %s\n", message.data);
  wasm_name_delete(&message);
}

////////////////////////////////////////////////////////////////////////////////
// Callbacks
////////////////////////////////////////////////////////////////////////////////

wasm_trap_t *emit_cb(const wasm_val_vec_t *args, wasm_val_vec_t *results) {
  putchar(args->data[0].of.i32);
  return NULL;
}

wasm_trap_t *read_cb(const wasm_val_vec_t *args, wasm_val_vec_t *results) {
  int n = 0;
  char *addr = &wasm_memory_data(memory)[args->data[0].of.i32];
  size_t len = args->data[1].of.i32;
  while (!(n = getline(&addr, &len, stdin))) {
  }
  if (n < 0) {
    n = 0;
  }
  results->data[0].kind = WASM_I32;
  results->data[0].of.i32 = n;
  return NULL;
}

wasm_trap_t *key_cb(const wasm_val_vec_t *args, wasm_val_vec_t *results) {
  struct termios old, current;
  tcgetattr(0, &old);
  current = old;
  current.c_lflag &= ~ICANON;
  current.c_lflag &= ~ECHO;
  tcsetattr(0, TCSANOW, &current);
  char ch = getchar();
  tcsetattr(0, TCSANOW, &old);
  results->data[0].kind = WASM_I32;
  results->data[0].of.i32 = ch;
  return NULL;
}

wasm_trap_t *load_cb(const wasm_val_vec_t *args, wasm_val_vec_t *results) {
  wasm_byte_t *addr = &wasm_memory_data(memory)[args->data[0].of.i32];
  size_t len = args->data[1].of.i32;
  wasm_byte_vec_t data = {.data = addr, .size = len};
  wasm_module_t *module = wasm_module_new(store, &data);
  if (!module) {
    return trap_from_string("error compiling module");
  }
  wasm_extern_t *externs[] = {wasm_table_as_extern(table), wasm_memory_as_extern(memory)};
  wasm_extern_vec_t imports = WASM_ARRAY_VEC(externs);
  wasm_trap_t *trap = NULL;
  wasm_instance_t *instance = wasm_instance_new(store, module, &imports, &trap);
  if (!instance) {
    assert(trap != NULL);
    return trap;
  }
  return NULL;
}

wasm_trap_t *call_cb(void *env, const wasm_val_vec_t *args, wasm_val_vec_t *results) {
  wasm_name_t message;
  wasm_name_new_from_string_nt(&message, "'call' not available in standalone");
  wasm_trap_t *trap = wasm_trap_new((wasm_store_t *)env, &message);
  wasm_name_delete(&message);
  return trap;
}

////////////////////////////////////////////////////////////////////////////////
// Main
////////////////////////////////////////////////////////////////////////////////

int main(int argc, char *argv_main[]) {
  wasm_engine_t *engine = wasm_engine_new();
  store = wasm_store_new(engine);
  wasm_byte_vec_t core = {.data = (wasm_byte_t *)waforth_core, .size = sizeof(waforth_core)};
  wasm_module_t *module = wasm_module_new(store, &core);
  if (!module) {
    printf("error compiling\n");
    return -1;
  }

  wasm_functype_t *emit_ft = wasm_functype_new_1_0(wasm_valtype_new_i32());
  wasm_func_t *emit_fn = wasm_func_new(store, emit_ft, emit_cb);
  wasm_functype_delete(emit_ft);

  wasm_functype_t *read_ft = wasm_functype_new_2_1(wasm_valtype_new_i32(), wasm_valtype_new_i32(), wasm_valtype_new_i32());
  wasm_func_t *read_fn = wasm_func_new(store, read_ft, read_cb);
  wasm_functype_delete(read_ft);

  wasm_functype_t *key_ft = wasm_functype_new_0_1(wasm_valtype_new_i32());
  wasm_func_t *key_fn = wasm_func_new(store, key_ft, key_cb);
  wasm_functype_delete(key_ft);

  wasm_functype_t *load_ft = wasm_functype_new_2_0(wasm_valtype_new_i32(), wasm_valtype_new_i32());
  wasm_func_t *load_fn = wasm_func_new(store, load_ft, load_cb);
  wasm_functype_delete(load_ft);

  wasm_functype_t *call_ft = wasm_functype_new_0_0();
  wasm_func_t *call_fn = wasm_func_new_with_env(store, call_ft, call_cb, store, NULL);
  wasm_functype_delete(call_ft);

  wasm_extern_t *externs[] = {wasm_func_as_extern(emit_fn), wasm_func_as_extern(read_fn), wasm_func_as_extern(key_fn), wasm_func_as_extern(load_fn),
                              wasm_func_as_extern(call_fn)};
  wasm_extern_vec_t imports = WASM_ARRAY_VEC(externs);
  wasm_trap_t *trap = NULL;
  wasm_instance_t *instance = wasm_instance_new(store, module, &imports, &trap);
  if (!instance) {
    printf("error instantiating core module\n");
    if (trap) {
      print_trap(trap);
      wasm_trap_delete(trap);
    }
    return -1;
  }

  wasm_extern_vec_t exports;
  wasm_instance_exports(instance, &exports);
  if (exports.size == 0) {
    printf("error accessing exports\n");
    return -1;
  }

  memory = wasm_extern_as_memory(exports.data[CORE_MEMORY_EXPORT_INDEX]);
  if (memory == NULL) {
    printf("error accessing `memory` export\n");
    return -1;
  }

  table = wasm_extern_as_table(exports.data[CORE_TABLE_EXPORT_INDEX]);
  if (table == NULL) {
    printf("error accessing `table` export\n");
    return -1;
  }

  const wasm_func_t *run_fn = wasm_extern_as_func(exports.data[CORE_RUN_EXPORT_INDEX]);
  if (run_fn == NULL) {
    printf("error accessing `interpret` export\n");
    return -1;
  }

  const wasm_func_t *error_fn = wasm_extern_as_func(exports.data[CORE_ERROR_EXPORT_INDEX]);
  if (error_fn == NULL) {
    printf("error accessing `error` export\n");
    return -1;
  }

  printf("WAForth (" VERSION ")\n");
  wasm_val_t run_as[1] = {WASM_I32_VAL(0)};
  wasm_val_vec_t run_args = WASM_ARRAY_VEC(run_as);
  wasm_val_vec_t run_results = WASM_EMPTY_VEC;

  wasm_val_vec_t err_args = WASM_EMPTY_VEC;
  wasm_val_t err_results_vs[] = {WASM_INIT_VAL};
  wasm_val_vec_t err_results = WASM_ARRAY_VEC(err_results_vs);

  for (int stopped = 0; !stopped;) {
    trap = wasm_func_call(run_fn, &run_args, &run_results);
    wasm_trap_t *etrap = wasm_func_call(error_fn, &err_args, &err_results);
    assert(etrap == NULL);
    switch (err_results.data[0].of.i32) {
    case ERR_QUIT:
    case ERR_ABORT:
      assert(trap != NULL);
      wasm_trap_delete(trap);
      break;
    case ERR_EOI:
      assert(trap == NULL);
      stopped = true;
      break;
    case ERR_BYE:
      assert(trap != NULL);
      wasm_trap_delete(trap);
      stopped = true;
      break;
    case ERR_UNKNOWN:
      assert(trap != NULL);
      print_trap(trap);
      wasm_trap_delete(trap);
      break;
    default:
      printf("unknown error: %d\n", err_results.data[0].of.i32);
      print_trap(trap);
      assert(false);
    }
  }

  wasm_extern_vec_delete(&exports);
  wasm_instance_delete(instance);
  wasm_func_delete(call_fn);
  wasm_func_delete(load_fn);
  wasm_func_delete(key_fn);
  wasm_func_delete(read_fn);
  wasm_func_delete(emit_fn);
  wasm_module_delete(module);
  wasm_store_delete(store);
  wasm_engine_delete(engine);
  return 0;
}
