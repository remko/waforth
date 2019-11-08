#!/usr/bin/env node

const process = require("process");
const fs = require("fs");

function escapeRegExp(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); // $& means the whole matched string
}

const file = process.argv[2];
const lines = fs
  .readFileSync(file)
  .toString()
  .split("\n");

const definitions = {};
lines.forEach(line => {
  Object.keys(definitions).forEach(k => {
    line = line.replace(
      new RegExp(escapeRegExp(k) + "(\\s|\\))", "g"),
      definitions[k] + " (; = " + k + " ;)$1"
    );
  });
  const m = line.match(/^;; \(define\s+([^\s]+)\s+([^\s]+)\)/);
  if (m) {
    definitions[m[1]] = m[2];
  } else {
    console.log(line);
  }
});
