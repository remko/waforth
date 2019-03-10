/* global __dirname, Buffer */
const fs = require("fs");
const path = require("path");
require("@babel/register")({
  presets: ["@babel/preset-env"]
});
const loadTests = require("./tests.js").default;
const wasmModule = fs.readFileSync(path.join(__dirname, "../src/waforth.wasm"));
loadTests(wasmModule, s => {
  return Buffer.from(s).toString("base64");
});
