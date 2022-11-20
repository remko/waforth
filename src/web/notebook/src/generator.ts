import fs from "fs";
import path from "path";
import { parseNotebook } from "./Notebook";
// eslint-disable-next-line @typescript-eslint/no-var-requires
const marked = require("../../../../node_modules/marked/lib/marked.cjs").marked;

declare let WAFNB_JS_PATH: string | undefined;
declare let WAFNB_CSS_PATH: string | undefined;

const titleRE = /^#[^#](.*)$/;

function escapeHTML(s: string) {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
export async function generate({
  file,
  css,
  js,
}: {
  bundle?: boolean;
  js?: string;
  css?: string;
  file: string;
}) {
  let outfile = file.replace(".wafnb", ".html");
  if (outfile === file) {
    outfile = outfile + ".html";
  }

  let style: string;
  let script: string;
  if (typeof WAFNB_JS_PATH !== "undefined") {
    const cssPath = path.relative(path.dirname(outfile), WAFNB_CSS_PATH!);
    const jsPath = path.relative(path.dirname(outfile), WAFNB_JS_PATH!);
    style = `<link rel="stylesheet" href="${cssPath}">`;
    script = `<script type="application/javascript" src="${jsPath}"></script>`;
  } else {
    style = `<style>${css}</style>`;
    script = `<script type="application/javascript">${js}</script>`;
  }

  const nb = parseNotebook(
    await fs.promises.readFile(file, {
      encoding: "utf-8",
      flag: "r",
    })
  );
  let title: string | null = null;
  let out: string[] = [];
  out.push(
    "<div class='banner'>Powered by <a target='_blank' rel='noreferrer' href='https://github.com/remko/waforth'>WAForth</a></div>"
  );
  out.push("<div class='content' data-hook='content'>");
  for (const cell of nb.cells) {
    switch (cell.kind) {
      case 1:
        if (title == null) {
          let m: RegExpExecArray | null = null;
          for (const v of cell.value.split("\n")) {
            m = titleRE.exec(v);
            if (m != null) {
              break;
            }
          }
          if (m != null) {
            title = m[1].trim();
          }
        }
        out.push(
          "<div class='text-cell'>" + marked.parse(cell.value) + "</div>"
        );
        break;
      case 2:
        out.push(
          "<div data-hook='code-cell' class='raw-code-cell'>" +
            escapeHTML(cell.value) +
            "</div>"
        );
        break;
      default:
        throw new Error("unexpected kind");
    }
  }
  out.push("</div>");

  out = [
    `<html><head><meta charset="utf-8"><title>${escapeHTML(
      title ?? ""
    )}</title>`,
    style,
    "</head>",
    "<body>",
    ...out,
    script,
    "</body></html>",
  ];
  return fs.promises.writeFile(outfile, out.join("\n"));
}
