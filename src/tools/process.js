#!/usr/bin/env node

const process = require("process");
const fs = require("fs");
const _ = require("lodash");

const args = process.argv.slice(2);
let enableBulkMemory = false;
if (args[0] === "--enable-bulk-memory") {
  enableBulkMemory = true;
  args.shift();
}
const [file, outfile] = args;

const lines = fs.readFileSync(file).toString().split("\n");

const definitions = {};
let skipLevel = 0;
let skippingDefinition = false;
let out = [];
lines.forEach((line) => {
  // Constants
  Object.keys(definitions).forEach((k) => {
    line = line.replace(
      new RegExp(
        "(\\s)([^\\s])+(\\s)+\\(; = " + _.escapeRegExp(k) + " ;\\)",
        "g"
      ),
      "$1" + definitions[k] + " (; = " + k + " ;)"
    );
  });
  const m = line.match(/^\s*;;\s+([!a-zA-Z0-9_]+)\s*:=\s*([^\s]+)/);
  if (m) {
    definitions[m[1]] = m[2];
  }

  // Bulk memory operations
  if (enableBulkMemory) {
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
    out.push(line);
  }

  if (skippingDefinition && skipLevel <= 0) {
    skippingDefinition = false;
  }
});

fs.writeFileSync(outfile, out.join("\n"));
