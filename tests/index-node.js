/* global __dirname */
const fs = require("fs");
const path = require("path");
require("@babel/register")({
  presets: ["@babel/preset-env"]
});
const loadTests = require("./tests.js").default;
const wasmModule = fs.readFileSync(path.join(__dirname, "../src/waforth.wasm"));
loadTests(wasmModule);
