#!/usr/bin/env node

const process = require("process");
const fs = require("fs");
const _ = require("lodash");

const file = process.argv[2];
const lines = fs
  .readFileSync(file)
  .toString()
  .split("\n");

const definitions = {};
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

  console.log(line);
});
