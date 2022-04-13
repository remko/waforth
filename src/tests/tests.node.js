const fs = require("fs");
const path = require("path");
require("@babel/register")({
  presets: ["@babel/preset-env"],
});
const loadTests = require("./suite.js").default;
const wasmModule = fs.readFileSync(path.join(__dirname, "../waforth.wasm"));
loadTests(wasmModule, (s) => {
  return Buffer.from(s).toString("base64");
});
