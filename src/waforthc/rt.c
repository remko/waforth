#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <termios.h>

#include "wasm-rt-exceptions.h"
#include "wasm-rt-impl.h"

#include "_waforth.h"
#include "_waforth_config.h"

#define ERR_UNKNOWN 0x1
#define ERR_QUIT 0x2
#define ERR_ABORT 0x3
#define ERR_EOI 0x4
#define ERR_BYE 0x5

#define MIN(a, b) (((a) < (b)) ? (a) : (b))

size_t initOffset = 0;

struct w2c_shell {
  wasm_rt_memory_t *memory;
};

void w2c_shell_emit(struct w2c_shell *mod, u32 c) {
  putchar(c);
}

u32 w2c_shell_read(struct w2c_shell *mod, u32 addr_, u32 len_) {
  size_t len = len_;
  char *addr = (char *)&mod->memory->data[addr_];
  int n = 0;
  if (sizeof(waforth_init) == 0) {
    // Read from stdin
    while (!(n = getline(&addr, &len, stdin))) {
    }
    if (n < 0) {
      n = 0;
    }
  } else {
    // Read from static input
    int nend = MIN((size_t)len, sizeof(waforth_init) - initOffset);
    for (; n < nend; ++n) {
      if (waforth_init[initOffset + n] == '\n') {
        n += 1;
        break;
      }
    }
    memcpy(addr, waforth_init + initOffset, n);
    initOffset += n;
  }
  return n;
}

u32 w2c_shell_key(struct w2c_shell *mod) {
  struct termios old, current;
  tcgetattr(0, &old);
  current = old;
  current.c_lflag &= ~ICANON;
  current.c_lflag &= ~ECHO;
  tcsetattr(0, TCSANOW, &current);
  char ch = getchar();
  tcsetattr(0, TCSANOW, &old);
  return ch;
}

u32 w2c_shell_random(struct w2c_shell *mod) {
  return random();
}

void w2c_shell_call(struct w2c_shell *mod) {
  printf("`call` not available in native compiled mode\n");
  wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE);
}

void w2c_shell_load(struct w2c_shell *mod, u32 addr, u32 len) {
  printf("Compilation is not available in native compiled mode\n");
  wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE);
}

int run(w2c_waforth *mod) {
  u32 err;

  wasm_rt_trap_t code = wasm_rt_impl_try();
  if (code == WASM_RT_TRAP_UNREACHABLE) {
  trap:
    err = w2c_waforth_error(mod);
    switch (err) {
    case ERR_QUIT:
    case ERR_ABORT:
    case ERR_UNKNOWN:
      break;
    case ERR_BYE:
      return 0;
    case ERR_EOI:
      return 0;
    default:
      printf("unknown error: %d\n", err);
      assert(false);
    }
  } else if (code != 0) {
    printf("trap %d\n", code);
    return -1;
  }
  w2c_waforth_run(mod, sizeof(waforth_init) > 0);
  goto trap;
}

int main(int argc, char *argv[]) {
  struct w2c_shell shell;
  w2c_waforth mod;

  wasm_rt_init();
  wasm2c_waforth_instantiate(&mod, &shell);
  shell.memory = w2c_waforth_memory(&mod);
  int ret = run(&mod);
  wasm2c_waforth_free(&mod);
  wasm_rt_free();
  return ret;
}
