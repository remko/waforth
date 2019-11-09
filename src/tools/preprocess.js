#!/usr/bin/env node

const process = require("process");
const fs = require("fs");
const _ = require("lodash");
const program = require("commander");

let file;
program
  .arguments("<file>")
  .option(
    "--enable-bulk-memory",
    "use bulk memory operations instead of own implementation"
  )
  .action(f => {
    file = f;
  });
program.parse(process.argv);

const lines = fs
  .readFileSync(file)
  .toString()
  .split("\n");

const definitions = {};
let skipLevel = 0;
let skippingDefinition = false;
lines.forEach(line => {
  // Constants
  Object.keys(definitions).forEach(k => {
    line = line.replace(
      new RegExp("(\\s)" + _.escapeRegExp(k) + "(\\s|\\))", "g"),
      "$1" + definitions[k] + " (; = " + k + " ;)$2"
    );
  });
  const m = line.match(/^;;\s+([!a-zA-Z0-9_]+)\s*:=\s*([^\s]+)/);
  if (m) {
    definitions[m[1]] = m[2];
  }

  // Bulk memory operations
  if (program.enableBulkMemory) {
    line = line
      .replace(/\(call \$memcopy/g, "(memory.copy")
      .replace(/\(call \$memset/g, "(memory.fill");
    if (line.match(/\(func (\$memset|\$memcopy)/)) {
      skippingDefinition = true;
      skipLevel = 0;
    }
  }
  if (skippingDefinition) {
    skipLevel += (line.match(/\(/g) || []).length;
    skipLevel -= (line.match(/\)/g) || []).length;
  }

  // Output line
  if (!skippingDefinition) {
    console.log(line);
  }

  if (skippingDefinition && skipLevel <= 0) {
    skippingDefinition = false;
  }
});
