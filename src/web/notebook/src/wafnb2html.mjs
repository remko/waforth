import wafnbJS from "../dist/wafnb.js";
import wafnbCSS from "../dist/wafnb.css";
import { generate } from "./generator";
import process from "process";

(async () => {
  const file = process.argv[2];
  if (file == null) {
    console.error("missing file");
    process.exit(-1);
  }
  await generate({ file, js: wafnbJS, css: wafnbCSS });
})();
