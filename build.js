#!/usr/bin/env node
/* eslint-env node */

const esbuild = require("esbuild");
const path = require("path");
const fs = require("fs");
const { createServer } = require("http");
const { promisify } = require("util");
const exec = promisify(require("child_process").exec);

function withWatcher(config, handleBuildFinished = () => {}, port = 8880) {
  const watchClients = [];
  createServer((req, res) => {
    return watchClients.push(
      res.writeHead(200, {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Access-Control-Allow-Origin": "*",
        Connection: "keep-alive",
      })
    );
  }).listen(port);
  return {
    ...config,
    banner: {
      js: `(function () { new EventSource("http://localhost:${port}").onmessage = function() { location.reload();};})();`,
    },
    watch: {
      async onRebuild(error, result) {
        if (error) {
          console.error(error);
        } else {
          // Doing this first, because this may do some ES5 transformations
          await handleBuildFinished(result);

          watchClients.forEach((res) => res.write("data: update\n\n"));
          watchClients.length = 0;
        }
      },
    },
  };
}

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

let buildConfig = {
  bundle: true,
  logLevel: "info",
  entryPoints: [
    path.join(__dirname, "src", "shell", "shell"),
    path.join(__dirname, "src", "tests", "tests"),
    path.join(__dirname, "src", "benchmarks", "benchmarks"),
  ],
  entryNames: dev ? "[name]" : "[name]-c$[hash]",
  assetNames: "[name]-c$[hash]",
  // target: "es6",
  outdir: path.join(__dirname, "public/waforth/dist"),
  external: ["fs", "stream", "util", "events"],
  minify: !dev,
  loader: {
    ".wasm": "binary",
    ".js": "jsx",
    ".png": "file",
    ".m4a": "file",
    ".woff2": "file",
    ".svg": "file",
    ".woff": "file",
    ".ttf": "file",
    ".eot": "file",
    ".md": "text",
  },
  sourcemap: true,
  metafile: true,
  plugins: [
    {
      name: "wat",
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
            namespace: "wat",
            watchFiles: [watPath],
          };
        });
        build.onLoad({ filter: /.*/, namespace: "wat" }, async (args) => {
          // Would be handy if we could get output from stdout without going through file
          const out = args.path.replace(".wat", ".wasm");
          const flags = "";
          // flags = --debug-names
          // console.log("wat: compiling %s", args.path);
          await exec(`wat2wasm ${flags} --output=${out} ${args.path}`);
          return {
            contents: await fs.promises.readFile(out),
            loader: "binary",
          };
        });
      },
    },
  ],
};

const INDEX_TEMPLATE = `<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <link href="/waforth/dist/$BASE.css" rel="stylesheet" />
    <title></title>
  </head>
  <body>
    <script type="text/javascript" src="/waforth/dist/$BASE.js"></script>
  </body>
</html>
`;
async function handleBuildFinished(result) {
  let index = INDEX_TEMPLATE.replace(/\$BASE/g, "shell");
  let testIndex = INDEX_TEMPLATE.replace(/\$BASE/g, "tests");
  let benchmarksIndex = INDEX_TEMPLATE.replace(/\$BASE/g, "benchmarks");
  // console.log(JSON.stringify(result.metafile.outputs, undefined, 2));
  for (const [out] of Object.entries(result.metafile.outputs)) {
    const outfile = path.basename(out);
    const sourcefile = outfile.replace(/-c\$[^.]+\./, ".");
    // console.log("%s -> %s", sourcefile, outfile);
    index = index.replace(`/${sourcefile}`, `/${outfile}`);
    testIndex = testIndex.replace(`/${sourcefile}`, `/${outfile}`);
    benchmarksIndex = benchmarksIndex.replace(`/${sourcefile}`, `/${outfile}`);
  }
  fs.writeFileSync("public/waforth/index.html", index);
  fs.mkdirSync("public/waforth/tests", { recursive: true });
  fs.writeFileSync("public/waforth/tests/index.html", testIndex);
  fs.mkdirSync("public/waforth/benchmarks", { recursive: true });
  fs.writeFileSync("public/waforth/benchmarks/index.html", benchmarksIndex);
}

if (watch) {
  // Simple static file server
  createServer(function (req, res) {
    let f = path.join(__dirname, "public", req.url);
    if (fs.lstatSync(f).isDirectory()) {
      f = path.join(f, "index.html");
    }
    fs.readFile(f, function (err, data) {
      if (err) {
        res.writeHead(404);
        res.end(JSON.stringify(err));
        return;
      }
      res.writeHead(200);
      res.end(data);
    });
  }).listen(8080);

  console.log("listening on port 8080");
  buildConfig = withWatcher(buildConfig, handleBuildFinished, 8081);
}
esbuild.build(buildConfig).then(handleBuildFinished, () => process.exit(1));
