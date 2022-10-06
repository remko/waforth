#!/usr/bin/env node
/* eslint-env node */
/* eslint @typescript-eslint/no-var-requires:0 */

const esbuild = require("esbuild");
const path = require("path");
const { execSync } = require("child_process");
const { wasmTextPlugin } = require("./scripts/esbuild/wasm-text");

let buildConfig = {
  bundle: true,
  logLevel: "info",
  entryPoints: [path.join(__dirname, "src", "web", "waforth")],
  outfile: path.join(__dirname, "dist", "index.js"),
  minify: true,
  format: "cjs",
  loader: {
    ".wasm": "binary",
  },
  sourcemap: true,
  plugins: [wasmTextPlugin({ debug: true })],
};

esbuild.build(buildConfig).then(
  () => {
    execSync(
      "node node_modules/typescript/bin/tsc --project tsconfig.package.json"
    );
  },
  () => process.exit(1)
);
