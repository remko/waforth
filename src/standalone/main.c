#include "waforth_core.h"
#include "wasm_export.h"
#include <stdio.h>

void waf_emit(wasm_exec_env_t exec_env, int c) {
  printf("%c", c);
}

int waf_read(wasm_exec_env_t exec_env, char *addr, size_t len) {
  int n = 0;
  while (!(n = getline(&addr, &len, stdin))) {
  }
  return n;
}

int waf_key(wasm_exec_env_t exec_env) {
  printf("key \n");
  return 0x20;
}

void waf_call(wasm_exec_env_t exec_env) {
  printf("error: call not implemented\n");
}

void waf_load(wasm_exec_env_t exec_env, int offset, int length, int index) {
  printf("load  %d %d %d\n", offset, length, index);
}

static NativeSymbol native_symbols[] = {
    {"emit", waf_emit, "(i)"},
    {"read", waf_read, "(*~)i"},
    {"key", waf_key, "()i"},
    {"call", waf_call, "()"},
    {"load", waf_load, /*"(*~i)"*/ "(iii)"},
};

int main(int argc, char *argv_main[]) {
  char error_buf[128];
  int ret = -1;

  if (!wasm_runtime_init()) {
    printf("Init runtime environment failed.\n");
    goto fail;
  }

  if (!wasm_runtime_register_natives("shell", native_symbols, sizeof(native_symbols) / sizeof(NativeSymbol))) {
    goto fail;
  }

  wasm_module_t module = wasm_runtime_load(waforth_core, sizeof(waforth_core), error_buf, sizeof(error_buf));
  if (!module) {
    printf("Load wasm module failed. error: %s\n", error_buf);
    goto fail;
  }

  uint32_t stack_size = 10485760, heap_size = 10485760;
  wasm_module_inst_t module_inst = wasm_runtime_instantiate(module, stack_size, heap_size, error_buf, sizeof(error_buf));
  if (!module_inst) {
    printf("Instantiate wasm module failed. error: %s\n", error_buf);
    goto fail;
  }

  wasm_exec_env_t exec_env = wasm_runtime_create_exec_env(module_inst, stack_size);
  if (!exec_env) {
    printf("Create wasm execution environment failed.\n");
    goto fail;
  }

  wasm_function_inst_t interpret = wasm_runtime_lookup_function(module_inst, "interpret", NULL);
  if (!interpret) {
    printf("The interpret wasm function is not found.\n");
    goto fail;
  }

  printf("WAForth\n");
  wasm_val_t results[1] = {{.kind = WASM_I32, .of.i32 = 0}};
  while (true) {
    if (!wasm_runtime_call_wasm_a(exec_env, interpret, 1, results, 0, NULL)) {
      printf("interpret failed. %s\n", wasm_runtime_get_exception(module_inst));
      goto fail;
    }
  }

  /*
    float ret_val;
    ret_val = results[0].of.f32;
    printf("Native finished calling wasm function generate_float(), returned a "
           "float value: %ff\n",
           ret_val);
           */

  ret = 0;

fail:
  if (exec_env) {
    wasm_runtime_destroy_exec_env(exec_env);
  }
  if (module_inst) {
    //   if (wasm_buffer)
    //     wasm_runtime_module_free(module_inst, wasm_buffer);
    wasm_runtime_deinstantiate(module_inst);
  }
  if (module) {
    wasm_runtime_unload(module);
  }
  wasm_runtime_destroy();

  printf("Done\n");
  return ret;
}
