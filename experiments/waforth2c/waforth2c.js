#!/usr/bin/env node

const fs = require("fs");
const process = require("process");

if (process.argv.length < 3) {
  console.log("Expected input file");
  process.exit(1);
}
const input = fs.readFileSync(process.argv[2]) + "";

const coreWasm = fs.readFileSync("../../src/waforth.wasm");

let core, table, memory, memory32;
const buffer = [];
const modules = [];
let tableSize = -1;

function run(s) {
  const data = new TextEncoder().encode(s);
  for (let i = data.length - 1; i >= 0; --i) {
    buffer.push(data[i]);
  }
  return core.exports.interpret();
}

function latest() {
  run("LATEST");
  const result = memory32[core.exports.tos() / 4 - 1];
  run("DROP");
  return result;
}

function here() {
  run("HERE");
  const result = memory32[core.exports.tos() / 4 - 1];
  run("DROP");
  return result;
}

WebAssembly.instantiate(coreWasm, {
  shell: {
    emit: c => {
      process.stdout.write(String.fromCharCode(c));
    },

    key: () => {
      if (buffer.length === 0) {
        return -1;
      }
      return buffer.pop();
    },

    debug: c => {
      process.stderr.write(String.fromCharCode(c));
    },

    load: (offset, length, index) => {
      let data = new Uint8Array(core.exports.memory.buffer, offset, length);
      if (index >= table.length) {
        table.grow(table.length);
      }
      tableSize = index + 1;
      var module = new WebAssembly.Module(data);
      modules.push(new Uint8Array(Array.from(data)));
      new WebAssembly.Instance(module, {
        env: { table, memory, tos: -1 }
      });
    }
  }
}).then(instance => {
  core = instance.instance;
  table = core.exports.table;
  memory = core.exports.memory;
  memory32 = new Int32Array(core.exports.memory.buffer, 0, 0x30000);
  const memory8 = new Uint8Array(core.exports.memory.buffer, 0, 0x30000);

  const dictionaryStart = latest();

  // Load prelude
  core.exports.loadPrelude();

  // Load code
  run(input);

  const savedLatest = latest();
  const savedHere = here();

  ////////////////////////////////////////////////////////////
  // Generate build files
  ////////////////////////////////////////////////////////////

  if (!fs.existsSync("waforth.gen")) {
    fs.mkdirSync("waforth.gen");
  }

  const make = [
    "waforth.gen/waforth_module_%.c waforth.gen/waforth_module_%.h: waforth.gen/waforth_module_%.wasm",
    "\twasm2c $< -o $(subst .wasm,.c,$<)",
    "",
    "waforth.gen/waforth_module_%.wasm: waforth.gen/waforth_module_%.in.wasm",
    "\twasm-dis $< -o $(subst .wasm,.wat,$@)",
    "\twasm-as $(subst .wasm,.wat,$@) -o $@",
    ""
  ];
  const include = [
    "#pragma once",
    "",
    "#define WAFORTH_LATEST " + savedLatest + "\n",
    "#define WAFORTH_HERE " + savedHere + "\n",
    "#define WAFORTH_TABLE_SIZE " + tableSize + "\n",
    "void waforth_modules_init();",
    "#undef WASM_RT_MODULE_PREFIX"
  ];
  const init = [
    "#include <memory.h>",
    '#include "waforth_modules.h"',
    "static const u8 dictionary[] = { " +
      Array.from(memory8.slice(dictionaryStart, savedHere)).join(", ") +
      " };",
    "void waforth_modules_init() {",
    "memcpy(&Z_envZ_memory->data[" +
      dictionaryStart +
      "], dictionary, " +
      (savedHere - dictionaryStart) +
      ");"
  ];
  const objects = ["waforth.gen/waforth_modules.o"];
  const moduleHeaders = [];
  const moduleSources = [];
  for (let i = 0; i < modules.length; ++i) {
    fs.writeFileSync(
      "waforth.gen/waforth_module_" + i + ".in.wasm",
      modules[i]
    );
    make.push(
      "waforth.gen/waforth_module_" +
        i +
        ".o: waforth.gen/waforth_module_" +
        i +
        ".c"
    );
    make.push(
      "\t$(CC) $(CPPFLAGS) $(CFLAGS) -DWASM_RT_MODULE_PREFIX=waforth_module_" +
        i +
        "_ -c $< -o $@"
    );
    make.push("");
    include.push("#define WASM_RT_MODULE_PREFIX waforth_module_" + i + "_");
    include.push('#include "waforth.gen/waforth_module_' + i + '.h"');
    include.push("#undef WASM_RT_MODULE_PREFIX");
    init.push("waforth_module_" + i + "_init();");
    objects.push("waforth.gen/waforth_module_" + i + ".o");
    moduleHeaders.push("waforth.gen/waforth_module_" + i + ".h");
    moduleSources.push("waforth.gen/waforth_module_" + i + ".c");
  }
  include.push("#define WASM_RT_MODULE_PREFIX");
  make.push("WAFORTH_MODULE_OBJECTS = " + objects.join(" ") + "\n");
  make.push("WAFORTH_MODULE_HEADERS = " + moduleHeaders.join(" ") + "\n");
  make.push("WAFORTH_MODULE_SOURCES = " + moduleSources.join(" ") + "\n");
  make.push("waforth.gen/waforth_modules.h: $(WAFORTH_MODULE_HEADERS)");
  init.push("}");
  fs.writeFileSync("waforth.gen/Makefile.inc", make.join("\n") + "\n");
  fs.writeFileSync("waforth.gen/waforth_modules.h", include.join("\n") + "\n");
  fs.writeFileSync("waforth.gen/waforth_modules.c", init.join("\n") + "\n");
});
