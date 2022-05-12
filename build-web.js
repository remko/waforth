#!/usr/bin/env node
/* eslint-env node */

const esbuild = require("esbuild");
const path = require("path");
const fs = require("fs");
const { createServer } = require("http");
const { wasmTextPlugin } = require("./scripts/esbuild/wasm-text");

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
    path.join(__dirname, "src", "web", "shell", "shell"),
    path.join(__dirname, "src", "web", "tests", "tests"),
    path.join(__dirname, "src", "web", "benchmarks", "benchmarks"),
    path.join(__dirname, "src", "web", "examples", "prompt", "prompt"),
    path.join(__dirname, "src", "web", "thurtle", "thurtle"),
  ],
  entryNames: dev ? "[name]" : "[name]-c$[hash]",
  assetNames: "[name]-c$[hash]",
  // target: "es6",
  outdir: path.join(__dirname, "public/waforth/dist"),
  publicPath: "/waforth/dist",
  external: ["fs", "stream", "util", "events"],
  minify: !dev,
  loader: {
    ".wasm": "binary",
    ".js": "jsx",
    ".fs": "text",
    ".f": "text",
    ".svg": "file",
  },
  define: {
    WAFORTH_VERSION: watch
      ? `"dev"`
      : // : `"${new Date().toISOString().replace(/T.|)}>#g, "")}"`,
        JSON.stringify(JSON.parse(fs.readFileSync("package.json")).version),
  },
  sourcemap: true,
  metafile: true,
  plugins: [
    wasmTextPlugin({ debug: true }),

    // Resolve 'waforth' to the main entrypoint (for examples)
    {
      name: "waforth",
      setup: (build) => {
        build.onResolve({ filter: /^waforth$/ }, () => {
          return { path: path.join(__dirname, "src", "web", "waforth.ts") };
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
    <link rel="shortcut icon" href="/waforth/favicon.ico" type="image/x-icon" />
    <link rel="icon" href="/waforth/favicon.ico" type="image/x-icon" />
    <link href="/waforth/dist/$BASE.css" rel="stylesheet" />
    <title>$TITLE</title>
  </head>
  <body>
    <script type="text/javascript" src="/waforth/dist/$BASE.js"></script>
  </body>
</html>
`;
async function handleBuildFinished(result) {
  const indexes = [
    ["WAForth", "shell", "public/waforth"],
    ["WAForth Tests", "tests", "public/waforth/tests"],
    ["WAForh Benchmarks", "benchmarks", "public/waforth/benchmarks"],
    ["WAForth Prompt Example", "prompt", "public/waforth/examples/prompt"],
    ["Thurtle", "thurtle", "public/thurtle", true],
  ];
  for (const [title, base, outpath, bs] of indexes) {
    let index = INDEX_TEMPLATE.replace(/\$BASE/g, base).replace(
      /\$TITLE/g,
      title
    );
    if (bs) {
      index = index.replace(
        "<body>",
        `<body>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-1BmE4kWBq78iYhFldvKuhfTAU6auU8tT94WrHftjDbrCEXSU1oBoqyl2QvZ6jIW3" crossorigin="anonymous" />
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js" integrity="sha384-ka7Sk0Gln4gmtz2MlQnikT1wXgYsOg+OMhuP+IlRH9sENBO0LRn5q+8nbTov4+1p" crossorigin="anonymous"></script>
`
      );
    }
    for (const [out] of Object.entries(result.metafile.outputs)) {
      const outfile = path.basename(out);
      const sourcefile = outfile.replace(/-c\$[^.]+\./, ".");
      // console.log("%s -> %s", sourcefile, outfile);
      index = index.replace(`/${sourcefile}`, `/${outfile}`);
    }
    await fs.promises.mkdir(outpath, { recursive: true });
    await fs.promises.writeFile(path.join(outpath, "index.html"), index);
  }
}

if (watch) {
  // Simple static file server
  createServer(async function (req, res) {
    let f = path.join(__dirname, "public", req.url);
    try {
      if ((await fs.promises.lstat(f)).isDirectory()) {
        f = path.join(f, "index.html");
      }
    } catch (e) {
      // pass
    }
    try {
      const data = await fs.promises.readFile(f);
      res.writeHead(
        200,
        req.url.endsWith(".svg")
          ? {
              "Content-Type": "image/svg+xml",
            }
          : undefined
      );
      res.end(data);
    } catch (err) {
      res.writeHead(404);
      res.end(JSON.stringify(err));
    }
  }).listen(8080);

  console.log("listening on port 8080");
  buildConfig = withWatcher(buildConfig, handleBuildFinished, 8081);
}

(async () => {
  await fs.promises.mkdir("public/waforth", { recursive: true });
  await fs.promises.copyFile(
    "public/favicon.ico",
    "public/waforth/favicon.ico"
  );
  try {
    handleBuildFinished(await esbuild.build(buildConfig));
  } catch (e) {
    process.exit(1);
  }
})();
