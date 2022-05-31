/* eslint-env node */

const { promisify } = require("util");
const exec = promisify(require("child_process").exec);
const path = require("path");

function wasmTextPlugin({ debug } = {}) {
  return {
    name: "wasm-text",
    setup(build) {
      build.onResolve({ filter: /.\.wat$/ }, async (args) => {
        if (args.resolveDir === "") {
          return;
        }
        const watPath = path.isAbsolute(args.path)
          ? args.path
          : path.join(args.resolveDir, args.path);
        return {
          path: watPath,
          namespace: "wasm-text",
          watchFiles: [watPath],
        };
      });
      build.onLoad({ filter: /.*/, namespace: "wasm-text" }, async (args) => {
        let flags = [];
        if (debug) {
          flags.push("--debug-names");
        }
        // console.log("wat: compiling %s", args.path);
        const r = await exec(
          `wat2wasm ${flags.join(" ")} --output=- ${args.path}`,
          { encoding: "buffer" }
        );
        return {
          contents: r.stdout,
          loader: "binary",
        };
      });
    },
  };
}

module.exports = {
  wasmTextPlugin,
};
