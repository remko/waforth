/* eslint-env node */

const { promisify } = require("util");
const exec = promisify(require("child_process").exec);
const fs = require("fs");
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
        // Would be handy if we could get output from stdout without going through file
        const out = `wat2wasm.${Math.floor(
          Math.random() * 1000000000
        )}.tmp.wasm`;
        try {
          let flags = [];
          if (debug) {
            flags.push("--debug-names");
          }
          // console.log("wat: compiling %s", args.path);
          await exec(
            `wat2wasm ${flags.join(" ")} --output=${out} ${args.path}`
          );
          return {
            contents: await fs.promises.readFile(out),
            loader: "binary",
          };
        } finally {
          try {
            await fs.promises.unlink(out);
          } catch (e) {
            // ignore
          }
        }
      });
    },
  };
}

module.exports = {
  wasmTextPlugin,
};
