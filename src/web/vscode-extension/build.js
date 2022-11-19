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

const config = {
  bundle: true,
  logLevel: "info",
  entryPoints: [path.join(__dirname, "src/extension.ts")],
  format: "cjs",
  minify: !dev,
  sourcemap: true,
  external: ["vscode"],
  loader: {
    ".wasm": "binary",
    ".fs": "text",
    ".svg": "dataurl",
  },
  plugins: [wasmTextPlugin({ debug: true })],
};

(async () => {
  try {
    await esbuild.build({
      ...config,
      outfile: path.join(__dirname, "dist/extension.js"),
      platform: "node",
    });
    await esbuild.build({
      ...config,
      outfile: path.join(__dirname, "dist/extension.web.js"),
      platform: "browser",
    });
  } catch (e) {
    process.exit(1);
  }
})();
