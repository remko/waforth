#include "waforth_core.h"
#include "wasm_c_api.h"
#include <stdio.h>

#define CORE_TABLE_EXPORT_INDEX 0
#define CORE_MEMORY_EXPORT_INDEX 1
#define CORE_INTERPRET_EXPORT_INDEX 6

wasm_memory_t *memory;
wasm_table_t *table;
wasm_store_t *store;

wasm_trap_t *trap_from_string(const char *s) {
  wasm_name_t message;
  wasm_name_new_from_string_nt(&message, s);
  wasm_trap_t *trap = wasm_trap_new(store, &message);
  wasm_name_delete(&message);
  return trap;
}

wasm_trap_t *emit_cb(const wasm_val_vec_t *args, wasm_val_vec_t *results) {
  printf("%c", args->data[0].of.i32);
  return NULL;
}

wasm_trap_t *read_cb(const wasm_val_vec_t *args, wasm_val_vec_t *results) {
  int n = 0;
  char *addr = &wasm_memory_data(memory)[args->data[0].of.i32];
  size_t len = args->data[1].of.i32;
  while (!(n = getline(&addr, &len, stdin))) {
  }
  results->data[0].kind = WASM_I32;
  results->data[0].of.i32 = n;
  return NULL;
}

wasm_trap_t *key_cb(const wasm_val_vec_t *args, wasm_val_vec_t *results) {
  // TODO
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
  wasm_instance_t *instance = wasm_instance_new(store, module, &imports, NULL);
  if (!instance) {
    return trap_from_string("error instantiating module");
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

// void print_frame(wasm_frame_t *frame) {
//   printf("> %p @ 0x%zx = %" PRIu32 ".0x%zx\n", wasm_frame_instance(frame), wasm_frame_module_offset(frame), wasm_frame_func_index(frame),
//          wasm_frame_func_offset(frame));
// }

void print_trap(wasm_trap_t *trap) {
  printf("Printing message...\n");
  wasm_name_t message;
  wasm_trap_message(trap, &message);
  printf("> %s\n", message.data);

  // printf("Printing origin...\n");
  // wasm_frame_t *frame = wasm_trap_origin(trap);
  // if (frame) {
  //   print_frame(frame);
  //   wasm_frame_delete(frame);
  // } else {
  //   printf("> Empty origin.\n");
  // }

  // printf("Printing trace...\n");
  // wasm_frame_vec_t trace;
  // wasm_trap_trace(trap, &trace);
  // if (trace.size > 0) {
  //   for (size_t i = 0; i < trace.size; ++i) {
  //     print_frame(trace.data[i]);
  //   }
  // } else {
  //   printf("> Empty trace.\n");
  // }

  // wasm_frame_vec_delete(&trace);
  wasm_trap_delete(trap);
  wasm_name_delete(&message);
}

int main(int argc, char *argv_main[]) {
  int ret = -1;

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

  wasm_functype_t *key_ft = wasm_functype_new_1_0(wasm_valtype_new_i32());
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
  wasm_instance_t *instance = wasm_instance_new(store, module, &imports, NULL);
  if (!instance) {
    printf("> Error instantiating module!\n");
    return -1;
  }

  wasm_extern_vec_t exports;
  wasm_instance_exports(instance, &exports);
  if (exports.size == 0) {
    printf("> Error accessing exports!\n");
    return -1;
  }

  memory = wasm_extern_as_memory(exports.data[CORE_MEMORY_EXPORT_INDEX]);
  if (memory == NULL) {
    printf("> Error accessing export!\n");
    return -1;
  }

  table = wasm_extern_as_table(exports.data[CORE_TABLE_EXPORT_INDEX]);
  if (table == NULL) {
    printf("> Error accessing export!\n");
    return -1;
  }

  const wasm_func_t *interpret_fn = wasm_extern_as_func(exports.data[CORE_INTERPRET_EXPORT_INDEX]);
  if (interpret_fn == NULL) {
    printf("> Error accessing export!\n");
    return -1;
  }

  wasm_val_vec_t args = WASM_EMPTY_VEC;
  wasm_val_vec_t results = WASM_EMPTY_VEC;
  wasm_trap_t *trap = wasm_func_call(interpret_fn, &args, &results);
  if (trap) {
    printf("> Error calling function!\n");
    print_trap(trap);
    return -1;
  }

  printf("Instantiated\n");

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
  printf("Done\n");
  return ret;
}
