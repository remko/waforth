#!/usr/bin/env node

// Usage: ./src/tools/generate-dictionary-entry.js "\$foo" FOO 0 0x21820 0x2182c 0xa1

const _ = require("lodash");
const process = require("process");

function encodeLE(n, align) {
  return (
    "\\u00" +
    _.padStart(n.toString(16), align * 2, "0")
      .match(/.{2}/g)
      .reverse()
      .join("\\u00")
  );
}

const funcName = process.argv[2];
const name = process.argv[3];
const flags = parseInt(process.argv[4]);
const latest = parseInt(process.argv[5]);
const here = parseInt(process.argv[6]);
const nextTableIndex = parseInt(process.argv[7]);

const dictionaryEntry = [
  encodeLE(latest, 4),
  encodeLE(name.length | flags, 1),
  _.padEnd(name, 4 * Math.floor((name.length + 4) / 4) - 1, "0"),
  encodeLE(nextTableIndex, 4),
];
console.log(
  "(data (i32.const 0x" +
    here.toString(16) +
    ') "' +
    dictionaryEntry.join('" "') +
    '")'
);
console.log(
  "(elem (i32.const 0x" + nextTableIndex.toString(16) + ") " + funcName + ")"
);
console.log("latest: 0x" + here.toString(16));
console.log(
  "here: 0x" +
    (here + dictionaryEntry.join("").replace(/\\u..../g, "_").length).toString(
      16
    )
);
console.log("!nextTableIndex: 0x" + (nextTableIndex + 1).toString(16));
