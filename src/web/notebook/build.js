#!/usr/bin/env node
/* eslint-env node */
/* eslint @typescript-eslint/no-var-requires:0 */

const esbuild = require("esbuild");
const path = require("path");
const fs = require("fs");
const { wasmTextPlugin } = require("../../../scripts/esbuild/wasm-text");

let dev = false;
let watch = false;
for (const arg of process.argv.slice(2)) {
  switch (arg) {
    case "--development":
      dev = true;
      break;
    case "--watch":
      watch = true;
      break;
  }
}

const buildConfig = {
  bundle: true,
  logLevel: "info",
  // target: "es6",
  minify: !dev,
  loader: {
    ".wasm": "binary",
    ".fs": "text",
  },
  plugins: [wasmTextPlugin({ debug: true })],
};

let nbBuildConfig = {
  ...buildConfig,
  outdir: path.join(__dirname, "dist"),
  entryPoints: [path.join(__dirname, "src", "wafnb.tsx")],
  publicPath: "/dist",
  assetNames: "[name].txt",
  sourcemap: !!dev,
  loader: {
    ...buildConfig.loader,
    ".svg": "dataurl",
  },
};

const generatorOutFile = path.join(
  __dirname,
  "..",
  "..",
  "..",
  "dist",
  "wafnb2html"
);

let generatorBuildConfig = {
  ...buildConfig,
  banner: { js: "#!/usr/bin/env node" },
  platform: "node",
  outfile: generatorOutFile,
  entryPoints: [path.join(__dirname, "src", "wafnb2html.mjs")],
  sourcemap: dev ? "inline" : undefined,
  loader: {
    ...buildConfig.loader,
    ".js": "text",
    ".css": "text",
  },
  define: watch
    ? {
        WAFNB_CSS_PATH: JSON.stringify(path.join(__dirname, "/dist/wafnb.css")),
        WAFNB_JS_PATH: JSON.stringify(path.join(__dirname, "/dist/wafnb.js")),
      }
    : undefined,
};

function handleGeneratorBuildFinished(result) {
  return fs.chmodSync(generatorOutFile, "755");
}

if (watch) {
  nbBuildConfig = {
    ...nbBuildConfig,
    watch: {
      async onRebuild(error) {
        if (error) {
          console.error(error);
        }
      },
    },
  };
  generatorBuildConfig = {
    ...generatorBuildConfig,
    watch: {
      async onRebuild(error, result) {
        if (error) {
          console.error(error);
          return;
        }
        return handleGeneratorBuildFinished(result);
      },
    },
  };
}

(async () => {
  try {
    await esbuild.build(nbBuildConfig);
    await handleGeneratorBuildFinished(
      await esbuild.build(generatorBuildConfig)
    );
  } catch (e) {
    process.exit(1);
  }
})();
