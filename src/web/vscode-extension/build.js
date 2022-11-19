#!/usr/bin/env node
/* eslint-env node */
/* eslint @typescript-eslint/no-var-requires:0 */

const esbuild = require("esbuild");
const path = require("path");
const { wasmTextPlugin } = require("../../../scripts/esbuild/wasm-text");

let dev = false;
for (const arg of process.argv.slice(2)) {
  switch (arg) {
    case "--development":
      dev = true;
      break;
  }
}

esbuild
  .build({
    bundle: true,
    logLevel: "info",
    entryPoints: [path.join(__dirname, "src/extension.ts")],
    outfile: path.join(__dirname, "dist/extension.js"),
    format: "cjs",
    minify: !dev,
    sourcemap: true,
    platform: "node",
    external: ["vscode"],
    loader: {
      ".wasm": "binary",
      ".fs": "text",
      ".svg": "dataurl",
    },
    plugins: [wasmTextPlugin({ debug: true })],
  })
  .catch(() => process.exit(1));
