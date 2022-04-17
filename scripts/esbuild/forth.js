/* eslint-env node */

const fs = require("fs");
const path = require("path");

function forthPlugin() {
  return {
    name: "forth",
    setup(build) {
      build.onResolve({ filter: /.\.f$/ }, async (args) => {
        if (args.resolveDir === "") {
          return;
        }
        const filePath = path.isAbsolute(args.path)
          ? args.path
          : path.join(args.resolveDir, args.path);
        return {
          path: filePath,
          namespace: "forth",
          watchFiles: [filePath],
        };
      });
      build.onLoad({ filter: /.*/, namespace: "forth" }, async (args) => {
        return {
          contents: await fs.promises.readFile(args.path),
          loader: "text",
        };
      });
    },
  };
}

module.exports = {
  forthPlugin,
};
