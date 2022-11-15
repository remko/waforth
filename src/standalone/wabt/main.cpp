#if defined(WIN32) || defined(_WIN32) || defined(__WIN32__) || defined(__NT__)
#include <windows.h>
#else
#include <termios.h>
#endif

#include <cstdio>

#include <wabt/binary-reader.h>
#include <wabt/interp/binary-reader-interp.h>
#include <wabt/interp/interp-util.h>
#include <wabt/interp/interp.h>
#include <wabt/result.h>

#include "waforth_core.h"

namespace wabti = wabt::interp;

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

static wabti::Store store;
static std::unique_ptr<wabt::FileStream> stderrStream;
static wabt::Features features;
static wabti::Memory::Ptr memory;
static wabti::Table::Ptr table;
static wabt::Errors errors;

FILE *input;

wabt::Result emit_cb(wabti::Thread &thread, const wabti::Values &params, wabti::Values &results, wabti::Trap::Ptr *trap) {
  putchar(params[0].Get<wabti::s32>());
  return wabt::Result::Ok;
}

wabt::Result key_cb(wabti::Thread &thread, const wabti::Values &params, wabti::Values &results, wabti::Trap::Ptr *trap) {
#if defined(WIN32) || defined(_WIN32) || defined(__WIN32__) || defined(__NT__)
  HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
  if (h == NULL) {
    return trap_from_string("no console");
  }
  DWORD mode;
  GetConsoleMode(h, &mode);
  SetConsoleMode(h, mode & ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT));
  TCHAR ch = 0;
  DWORD cc;
  ReadConsole(h, &ch, 1, &cc, NULL);
  SetConsoleMode(h, mode);
#else
  struct termios old, current;
  tcgetattr(0, &old);
  current = old;
  current.c_lflag &= ~ICANON;
  current.c_lflag &= ~ECHO;
  tcsetattr(0, TCSANOW, &current);
  char ch = getchar();
  tcsetattr(0, TCSANOW, &old);
#endif
  results[0].Set((wabti::u32)ch);
  return wabt::Result::Ok;
}

wabt::Result read_cb(wabti::Thread &thread, const wabti::Values &params, wabti::Values &results, wabti::Trap::Ptr *trap) {
  auto addr = (char *)memory->UnsafeData() + params[0].Get<wabti::s32>();
  auto size = params[1].Get<wabti::s32>();
  *addr = 0;
  fgets(addr, size, input);
  int n = strlen(addr);
  results[0].Set((wabti::u32)n);
  return wabt::Result::Ok;
}

wabt::Result load_cb(wabti::Thread &thread, const wabti::Values &params, wabti::Values &results, wabti::Trap::Ptr *trap) {
  auto addr = params[0].Get<wabti::s32>();
  auto size = params[1].Get<wabti::s32>();
  wabti::ModuleDesc desc;
  CHECK_RESULT(wabti::ReadBinaryInterp("word.wasm", memory->UnsafeData() + addr, size, wabt::ReadBinaryOptions(features, nullptr, true, true, true),
                                       &errors, &desc));
  auto mod = wabti::Module::New(store, desc);
  wabti::RefVec imports = {table.ref(), memory.ref()};
  auto modi = wabti::Instance::Instantiate(store, mod.ref(), imports, trap);
  if (!modi) {
    printf("error instantiating word module\n");
    return wabt::Result::Error;
    ;
  }
  return wabt::Result::Ok;
}

wabt::Result call_cb(wabti::Thread &thread, const wabti::Values &params, wabti::Values &results, wabti::Trap::Ptr *trap) {
  printf("`call` is not available in standalone\n");
  return wabt::Result::Error;
}

wabt::Result run(bool interactive) {
  stderrStream = wabt::FileStream::CreateStderr();

  // Load core module
  wabti::ModuleDesc desc;
  CHECK_RESULT(wabti::ReadBinaryInterp("waforth.wasm", waforth_core, sizeof(waforth_core),
                                       wabt::ReadBinaryOptions(features, nullptr, true, true, true), &errors, &desc));
  auto core = wabti::Module::New(store, desc);

  // Core Exports
  wabti::Func::Ptr errorFn;
  wabti::Func::Ptr runFn;

  // Bind core imports
  wabti::RefVec imports;
  for (auto &&import : core->desc().imports) {
    if (import.type.type->kind == wabti::ExternKind::Func && import.type.module == "shell") {
      auto ft = *wabt::cast<wabti::FuncType>(import.type.type.get());
      wabti::HostFunc::Callback cb;
      if (import.type.name == "emit") {
        cb = emit_cb;
      } else if (import.type.name == "read") {
        cb = read_cb;
      } else if (import.type.name == "key") {
        cb = key_cb;
      } else if (import.type.name == "load") {
        cb = load_cb;
      } else if (import.type.name == "call") {
        cb = call_cb;
      } else {
        printf("Unknown import: %s\n", import.type.name.c_str());
        return wabt::Result::Error;
      }
      auto func = wabti::HostFunc::New(store, ft, cb);
      imports.push_back(func.ref());
      continue;
    }
    imports.push_back(wabti::Ref::Null);
  }

  // Instantiate module
  wabti::Trap::Ptr trap;
  auto corei = wabti::Instance::Instantiate(store, core.ref(), imports, &trap);
  if (!corei) {
    printf("error instantiating module\n");
    if (trap) {
      wabti::WriteTrap(stderrStream.get(), " error ", trap);
    }
    return wabt::Result::Error;
  }

  // Load exports
  for (auto &&export_ : core->desc().exports) {
    if (export_.type.type->kind == wabt::ExternalKind::Memory) {
      memory = store.UnsafeGet<wabti::Memory>(corei->memories()[export_.index]);
    } else if (export_.type.type->kind == wabt::ExternalKind::Table) {
      table = store.UnsafeGet<wabti::Table>(corei->tables()[export_.index]);
    } else if (export_.type.name == "run") {
      runFn = store.UnsafeGet<wabti::Func>(corei->funcs()[export_.index]);
    } else if (export_.type.name == "error") {
      errorFn = store.UnsafeGet<wabti::Func>(corei->funcs()[export_.index]);
    }
  }

  // Run
  wabti::Values runParams = {wabti::Value::Make(interactive ? 0 : 1)};
  wabti::Values runResults;
  wabti::Values errorParams;
  wabti::Values errorResults;
  for (int stopped = false; !stopped;) {
    auto runRes = runFn->Call(store, runParams, runResults, &trap, nullptr);
    CHECK_RESULT(errorFn->Call(store, errorParams, errorResults, &trap, nullptr));
    switch (errorResults[0].Get<wabti::s32>()) {
    case ERR_QUIT:
    case ERR_ABORT:
      assert(!Succeeded(runRes));
      break;
    case ERR_EOI:
      assert(Succeeded(runRes));
      stopped = true;
      break;
    case ERR_BYE:
      assert(!Succeeded(runRes));
      stopped = true;
      break;
    case ERR_UNKNOWN:
      assert(!Succeeded(runRes));
      if (trap) {
        wabti::WriteTrap(stderrStream.get(), " error ", trap);
      } else {
        printf("unknown error\n");
      }
      break;
    default:
      printf("unknown error code\n");
      if (trap) {
        wabti::WriteTrap(stderrStream.get(), " error ", trap);
      }
      assert(false);
    }
  }
  return wabt::Result::Ok;
}

int main(int argc, char *argv[]) {
  if (argc >= 2) {
    input = fopen(argv[1], "r");
  } else {
    input = stdin;
  }

  if (input == stdin) {
    printf("WAForth (" VERSION ")\n");
  }

  auto result = run(input == stdin);

  if (input != stdin) {
    fclose(input);
  }

  return Succeeded(result) ? 0 : 1;
}