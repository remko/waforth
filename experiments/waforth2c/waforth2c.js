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

    getc: () => {
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

  const make = [];
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
  const moduleFiles = [];
  for (let i = 0; i < modules.length; ++i) {
    fs.writeFileSync("waforth.gen/waforth_module_" + i + ".wasm", modules[i]);
    include.push("#define WASM_RT_MODULE_PREFIX waforth_module_" + i + "_");
    include.push('#include "waforth.gen/waforth_module_' + i + '.h"');
    include.push("#undef WASM_RT_MODULE_PREFIX");
    init.push("waforth_module_" + i + "_init();");
    moduleFiles.push("waforth.gen/waforth_module_" + i + ".wasm");
  }
  include.push("#define WASM_RT_MODULE_PREFIX");
  make.push("WAFORTH_MODULES = " + moduleFiles.join(" ") + "\n");
  init.push("}");
  fs.writeFileSync("waforth.gen/Makefile.inc", make.join("\n") + "\n");
  fs.writeFileSync("waforth.gen/waforth_modules.h", include.join("\n") + "\n");
  fs.writeFileSync("waforth.gen/waforth_modules.c", init.join("\n") + "\n");
});
