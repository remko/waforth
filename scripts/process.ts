#!/usr/bin/env yarn exec ts-node --

import * as process from "process";
import * as fs from "fs";
import * as _ from "lodash";
import simpleEval from "simple-eval";
import { assert } from "console";

let inplace = false;
let addDict: string | undefined = undefined;
for (let i = 2; i < process.argv.length; i++) {
  const arg = process.argv[i];
  switch (arg) {
    case "--inplace":
      inplace = true;
      break;
    case "--add-dict":
      addDict = process.argv[i + 1];
      i += 1;
      break;
  }
}

type DictElement = {
  type: "dict";
  offset: number;
  prev: number;
  flags: number;
  name: string;
  index: number;
  indexExpr?: string;
  data?: string;
  dataExpr?: string;

  // Added afterwards
  func?: string;
};

type StringElement = {
  type: "string";
  offset: number;
  string: string;
};

type DataElement = DictElement | StringElement;

function unescapeString(s: string) {
  return s.replace(/\\(..)/, (str: string, ...args: any[]) => {
    return String.fromCharCode(parseInt(args[0], 16));
  });
}

function escapeString(s: string) {
  return s.replace("\\", "\\5c").replace('"', "\\22");
}

function unpack(s: string): number {
  let n = 0;
  for (const ch of s
    .split(/(\\..|[^\\])/)
    .filter((x) => x != "")
    .reverse()) {
    n = n << 8;
    if (ch.startsWith("\\")) {
      n += parseInt(ch.slice(1), 16);
    } else {
      n += ch.charCodeAt(0);
    }
  }
  return n;
}

function pack(n: number) {
  const acc = [];
  while (n > 0) {
    acc.push(n % 256);
    n = Math.floor(n / 256);
  }
  while (acc.length < 4) {
    acc.push(0);
  }
  return acc.map((x) => "\\" + _.padStart(x.toString(16), 2, "0")).join("");
}

function toHex(n: number) {
  return (n < 0 ? "-" : "") + "0x" + Math.abs(n).toString(16);
}

function parseExpr(s: string | undefined): string | undefined {
  if (s == null) {
    return undefined;
  }
  const m = s.match(/\(; =(.*) ;\)/);
  if (m == null) {
    throw new Error("unparseable expression: " + s);
  }
  let expr = m[1].trim();
  if (expr.startsWith("body(") && expr.endsWith(")")) {
    expr = 'body("' + expr.substring(5, expr.length - 1) + '")';
  }
  if (expr.startsWith("'") && expr.endsWith("'")) {
    expr = "ord(" + expr + ")";
  }
  return expr;
}

function parseDataElement(line: string): DataElement | null {
  if (!line.match(/^\s*\(data\s+/)) {
    return null;
  }
  if (line.match(/= MODULE_HEADER_BASE/)) {
    return null;
  }

  let m: RegExpMatchArray | null;
  if ((m = line.match(/^\s*\(data \(i32.const (\w+)\) "\\.." "([^"]+)"/))) {
    return {
      type: "string",
      offset: parseInt(m[1]),
      string: unescapeString(m[2]),
    };
  } else if (
    (m = line.match(
      /^\s*\(data \(i32.const (\w+)\) "([^"]+)" "([^"]+)"( \(;[^;]+;\))? "([^"]+)" "([^"]+)"( \(;[^;]+;\))?( "([^"]+)"( \(;[^;]+;\))?)?\)/
    ))
  ) {
    return {
      type: "dict",
      offset: parseInt(m[1]),
      prev: unpack(m[2]),
      flags: unpack(m[3]) & 0xe0,
      name: unescapeString(m[5]).substring(0, unpack(m[3]) & 0x1f),
      index: unpack(m[6]),
      indexExpr: parseExpr(m[7]),
      data: m[9],
      dataExpr: parseExpr(m[10]),
    };
  }
  throw new Error("unmatched data section: " + line);
}

const wat_file = "src/waforth.wat";

const args = process.argv.slice(2);

let lines = fs.readFileSync(wat_file).toString().split("\n");

const updateValues = true;

////////////////////////////////////////////////////////////////////////
// Collect information
////////////////////////////////////////////////////////////////////////

const stringElements: StringElement[] = [];
let dictElements: DictElement[] = [];
const definitions: Record<string, number> = {};
let currentFunc: string;
for (let line of lines) {
  // Parse function name
  let m = line.match(/\s*\(func ([^\s]+)\s/);
  if (m != null) {
    currentFunc = m[1];
  }

  const dataElement = parseDataElement(line);
  if (dataElement != null) {
    switch (dataElement.type) {
      case "string":
        stringElements.push(dataElement);
        break;
      case "dict":
        dictElements.push({ ...dataElement, func: currentFunc! });
        break;
      default:
        assert(false);
    }
  }

  // Parse definitions
  m = line.match(/^\s*;;\s+([!a-zA-Z0-9_]+)\s*:=\s*([^\s]+)/);
  if (m) {
    if (isNaN(m[2] as any)) {
      throw new Error("unparseable definition: " + m[2]);
    }
    definitions[m[1]] = parseInt(m[2]);
  }
}

////////////////////////////////////////////////////////////////////////
// Add new entry
////////////////////////////////////////////////////////////////////////

let addDictElement: DictElement | undefined = undefined;
if (addDict) {
  addDictElement = {
    type: "dict",
    offset: -1,
    prev: -1,
    flags: 0,
    name: addDict,
    index: 0xffffffff,
    func: "$" + addDict,
  };
  let i = 0;
  for (; i < dictElements.length; ++i) {
    if (dictElements[i].name.localeCompare(addDictElement.name) > 0) {
      break;
    }
  }
  dictElements.splice(i, 0, addDictElement);
}

////////////////////////////////////////////////////////////////////////
// Update data elements
////////////////////////////////////////////////////////////////////////

let offset = definitions.DATA_SPACE_BASE;
for (const el of stringElements) {
  el.offset = offset;
  offset += 1 + el.string.length;
}

offset = Math.ceil(offset / 4) * 4;
let prevDictOffset = 0;
let nextTableIndex = 0x10;
for (const el of dictElements) {
  el.prev = prevDictOffset;
  el.offset = prevDictOffset = offset;
  offset +=
    4 + Math.ceil((1 + el.name.length) / 4) * 4 + 4 + (el.data != null ? 4 : 0);
  if (el.indexExpr == null) {
    el.index = nextTableIndex;
    nextTableIndex += 1;
  }
}

const here = offset;

function serializeWordData(el: DictElement): string {
  const paddedName = _.padEnd(
    el.name,
    Math.ceil((1 + el.name.length) / 4) * 4 - 1,
    " "
  );
  const flagsLen =
    "\\" + _.padStart((el.name.length | el.flags).toString(16), 2, "0");
  let l = `  (data (i32.const 0x${el.offset.toString(16)})`;
  l += ` "${pack(el.prev)}"`;
  l += ` "${flagsLen}"`;
  if (el.flags !== 0) {
    const flags = [];
    if (el.flags & 0x20) {
      flags.push("F_HIDDEN");
    }
    if (el.flags & 0x40) {
      flags.push("F_DATA");
    }
    if (el.flags & 0x80) {
      flags.push("F_IMMEDIATE");
    }
    l += ` (; ${flags.join(" & ")} ;)`;
  }
  l += ` "${escapeString(paddedName)}"`;
  l += ` "${pack(el.index)}"`;
  if (el.indexExpr) {
    l += ` (; = ${el.indexExpr} ;)`;
  }
  if (el.data) {
    l += ` "${el.data}"`;
    if (el.dataExpr) {
      l += ` (; = ${el.dataExpr} ;)`;
    }
  }
  l += ")";
  return l;
}

function serializeStringData(el: StringElement): string {
  const offset = "0x" + el.offset.toString(16);
  const len = "\\" + _.padStart(el.string.length.toString(16), 2, "0");
  return `  (data (i32.const ${offset}) "${len}" "${escapeString(el.string)}")`;
}

let newLines = [];
for (const line of lines) {
  const dataElement = parseDataElement(line);
  if (dataElement != null) {
    switch (dataElement.type) {
      case "string": {
        const el = stringElements.find((e) => e.string === dataElement.string)!;
        assert(el != null);
        newLines.push(serializeStringData(el));
        break;
      }
      case "dict": {
        const el = dictElements.find((e) => e.name === dataElement.name);
        if (el == null) {
          newLines.push(line);
          continue;
        }
        newLines.push(serializeWordData(el));
        break;
      }
      default:
        assert(false);
    }
  } else {
    // TODO: Update new HERE
    newLines.push(line);
  }
}
lines = newLines;

////////////////////////////////////////////////////////////////////////
// Validate
////////////////////////////////////////////////////////////////////////

if (!updateValues) {
  for (const de of dictElements) {
    const exprVals: [string | undefined, unknown][] = [
      [de.indexExpr, de.index],
      [de.dataExpr, de.data],
    ];
    for (const [expr, val] of exprVals) {
      if (expr != null) {
        let x = simpleEval(expr, { ...definitions, pack });
        if (typeof val === "number" && typeof x === "string") {
          x = unpack(x);
        }
        if (x != val) {
          throw new Error(
            `expression does not match value: ${JSON.stringify(
              de
            )} -> ${val} != ${x}`
          );
        }
      }
    }
  }
}

////////////////////////////////////////////////////////////////////////
// Update expression values
////////////////////////////////////////////////////////////////////////

function body(w: string) {
  const el = dictElements.find((e) => e.name === w);
  if (el == null) {
    throw new Error("dict entry not found: " + w);
  }
  return (
    el.offset +
    4 +
    Math.ceil((1 + el.name.length) / 4) * 4 +
    (el.flags & 0x40 ? 4 : 0)
  );
}

function str(s: string) {
  const sel = stringElements.find((e) => e.string === s);
  if (sel == null) {
    throw new Error("string not found: " + s);
  }
  return sel.offset;
}

function len(s: string) {
  return s.length;
}

function ord(s: string) {
  return s.charCodeAt(0);
}

function index(w: string) {
  const el = dictElements.find((e) => e.name === w);
  if (el == null) {
    throw new Error("dict entry not found: " + w);
  }
  return el.index;
}

if (updateValues) {
  const updatedLines: string[] = [];
  for (let line of lines) {
    line = line.replace(
      new RegExp("(\\s)([^\\s]+)(\\s)+(\\(; =[^;]+;\\))", "g"),
      (s: string, ...args: any[]) => {
        const expr = parseExpr(args[3]);
        const val = simpleEval(expr!, {
          ...definitions,
          pack,
          body,
          index,
          str,
          len,
          ord,
        });
        const sval = _.isString(val) ? '"' + val + '"' : toHex(val as number);
        return args[0] + sval + args[2] + args[3];
      }
    );

    let m = line.match(
      /(.*\(global ([^\s]+) \(mut i32\) \(i32.const )([^\)\s]+)(\).*)/
    );
    if (m != null) {
      const [prefix, global, val, suffix] = m.slice(1);
      if (global === "$here") {
        line = prefix + "0x" + here.toString(16) + suffix;
      } else if (global === "$latest") {
        line =
          prefix +
          "0x" +
          dictElements[dictElements.length - 1].offset.toString(16) +
          suffix;
      } else if (global === "$nextTableIndex") {
        line = prefix + "0x" + nextTableIndex.toString(16) + suffix;
      }
    }

    m = line.match(/(.*\(table .* )([^\s]+)( funcref\))/);
    if (m != null) {
      line = m[1] + "0x" + nextTableIndex.toString(16) + m[3];
    }

    m = line.match(/\s*\(elem \(i32.const ([^\)]+)\) ([^\)]+)\)/);
    if (m != null) {
      const func = m[2];
      const el = dictElements.find((e) => e.func === func);
      if (el == null) {
        continue;
      }
      line = `  (elem (i32.const 0x${el.index.toString(16)}) ${func})`;
    }

    updatedLines.push(line);
  }
  lines = updatedLines;
}

////////////////////////////////////////////////////////////////////////
// Strip
////////////////////////////////////////////////////////////////////////

// const strippedLines: string[] = [];
// let skipLevel = 0;
// let skippingDefinition = false;
// for (let line of lines) {
//   if (enableBulkMemory) {
//     line = line
//       .replace(/\(call \$memcopy/g, "(memory.copy")
//       .replace(/\(call \$memset/g, "(memory.fill");
//     if (line.match(/\(func (\$memset|\$memcopy)/)) {
//       skippingDefinition = true;
//       skipLevel = 0;
//     }
//   }
//   if (skippingDefinition) {
//     skipLevel += (line.match(/\(/g) || []).length;
//     skipLevel -= (line.match(/\)/g) || []).length;
//   }

//   // Output line
//   if (!skippingDefinition) {
//     strippedLines.push(line);
//   }

//   if (skippingDefinition && skipLevel <= 0) {
//     skippingDefinition = false;
//   }
// }
// lines = strippedLines;

fs.writeFileSync(
  inplace ? "src/waforth.wat" : "src/waforth.out.wat",
  lines.join("\n")
);

if (addDictElement) {
  console.log(`  (func $${addDictElement.name} (param $tos i32) (result i32))`);
  console.log(serializeWordData(addDictElement));
  console.log(
    `  (elem (i32.const 0x${addDictElement.index.toString(16)}) $${
      addDictElement.name
    })`
  );
}
