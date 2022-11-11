#include <assert.h>
#include <stdio.h>
#include <termios.h>

#include <wasm-rt-impl.h>

#include "_waforth.h"
#include "_waforth_config.h"

#define ERR_UNKNOWN 0x1
#define ERR_QUIT 0x2
#define ERR_ABORT 0x3
#define ERR_EOI 0x4
#define ERR_BYE 0x5

#define MIN(a,b) (((a)<(b))?(a):(b))

size_t initOffset = 0;

struct Z_shell_instance_t {
  wasm_rt_memory_t *memory;
};

void Z_shellZ_emit(struct Z_shell_instance_t *mod, u32 c) {
  putchar(c);
}

u32 Z_shellZ_read(struct Z_shell_instance_t *mod, u32 addr_, u32 len_) {
  unsigned long len = len_;
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

u32 Z_shellZ_key(struct Z_shell_instance_t *mod) {
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

void Z_shellZ_call(struct Z_shell_instance_t *mod) {
  printf("`call` not available in native compiled mode\n");
  wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE);
}

void Z_shellZ_load(struct Z_shell_instance_t *mod, u32 addr, u32 len) {
  printf("Compilation is not available in native compiled mode\n");
  wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE);
}

int run(Z_waforth_instance_t *mod) {
  u32 err;

  wasm_rt_trap_t code = wasm_rt_impl_try();
  if (code == WASM_RT_TRAP_UNREACHABLE) {
  trap:
    err = Z_waforthZ_error(mod);
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
  Z_waforthZ_run(mod, sizeof(waforth_init) > 0);
  goto trap;
}

int main(int argc, char *argv[]) {
  struct Z_shell_instance_t shell;
  Z_waforth_instance_t mod;

  wasm_rt_init();
  Z_waforth_init_module();
  Z_waforth_instantiate(&mod, &shell);
  shell.memory = Z_waforthZ_memory(&mod);
  int ret = run(&mod);
  Z_waforth_free(&mod);
  wasm_rt_free();
  return ret;
}
