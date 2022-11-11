#include <wabt/apply-names.h>
#include <wabt/binary-reader-ir.h>
#include <wabt/binary-reader.h>
#include <wabt/binary-writer.h>
#include <wabt/error-formatter.h>
#include <wabt/generate-names.h>
#include <wabt/interp/binary-reader-interp.h>
#include <wabt/interp/interp-util.h>
#include <wabt/interp/interp.h>
#include <wabt/ir.h>
#include <wabt/stream.h>
#include <wabt/validator.h>

#include "waforth_core.h"

int main(int argc, char *argv[]) {
  wabt::Errors errors;
  wabt::Features features;
  wabt::Module mod;
  auto result = ReadBinaryIr("in.wasm", waforth_core, sizeof(waforth_core), wabt::ReadBinaryOptions(features, NULL, true, true, true), &errors, &mod);
  assert(Succeeded(result));
  result = ValidateModule(&mod, &errors, wabt::ValidateOptions(features));
  result |= GenerateNames(&mod);
  assert(Succeeded(result));
  result = ApplyNames(&mod);
  assert(Succeeded(result));

  wabt::FileStream out("out.wasm");
  result = wabt::WriteBinaryModule(&out, &mod, wabt::WriteBinaryOptions(features, false, false, true));
  assert(Succeeded(result));

  return 0;
}
