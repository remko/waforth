/*eslint-env node*/

const path = require("path");
const HtmlWebpackPlugin = require("html-webpack-plugin");
const webpack = require("webpack");

function config({ entry, outputDir, title, template, mode }) {
  mode = mode || "development";
  const result = {
    mode,
    entry,
    output: {
      filename: "index.js",
      path: path.resolve(__dirname, "dist", outputDir),
      publicPath: "/" + outputDir
    },
    module: {
      rules: [
        {
          test: /\.js$|\.jsx$/,
          exclude: /node_modules/,
          use: {
            loader: "babel-loader",
            options: {
              presets: ["es2015"],
              plugins: [["transform-react-jsx", { pragma: "h" }]]
            }
          }
        },
        {
          test: /\.css$/,
          use: [{ loader: "style-loader" }, { loader: "css-loader" }]
        },
        {
          test: /\.wasm$/,
          exclude: /node_modules/,
          type: "javascript/auto",
          use: { loader: "bin-loader" }
        }
      ]
    },
    plugins: [
      new webpack.ContextReplacementPlugin(/mocha\/lib/, "", false),
      new HtmlWebpackPlugin(
        Object.assign(
          {
            title,
            meta: {
              viewport: "width=device-width, initial-scale=1, shrink-to-fit=no"
            }
          },
          template ? { template } : {}
        )
      )
    ],
    node: {
      fs: "empty"
    }
  };
  if (mode === "development") {
    result.devtool = "cheap-module-eval-source-map";
  } else {
    result.devtool = "source-map";
  }
  return result;
}

module.exports = (env, argv) => [
  config({
    title: "WAForth",
    template: "./src/shell/index.html",
    entry: "./src/shell/index.js",
    outputDir: "waforth",
    mode: argv.mode
  }),
  config({
    title: "WAForth Unit Tests",
    template: "./tests/index.html",
    entry: "./tests/index.js",
    outputDir: "tests",
    mode: argv.mode
  }),
  config({
    title: "Benchmarks",
    entry: "./tests/benchmarks/index.js",
    outputDir: "benchmarks",
    mode: argv.mode
  })
];
