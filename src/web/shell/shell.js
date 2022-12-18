/* global WAFORTH_VERSION */

import WAForth, { withCharacterBuffer } from "../waforth";
import "./shell.css";

const version =
  typeof WAFORTH_VERSION !== "undefined" ? WAFORTH_VERSION : "dev";

const forth = new WAForth();

const consoleEl = document.createElement("pre");
consoleEl.className = "console";
document.body.appendChild(consoleEl);

let inputEl;
let cursorEl;

consoleEl.addEventListener("click", () => {
  inputEl.style.visibility = "visible";
  inputEl.focus();
  inputEl.style.visibility = "hidden";
});

let currentConsoleEl;
let currentConsoleElIsInput = false;
let outputBuffer = [];
function flush() {
  if (outputBuffer.length == 0) {
    return;
  }
  currentConsoleEl.appendChild(document.createTextNode(outputBuffer.join("")));
  outputBuffer = [];
  document.querySelector(".cursor").scrollIntoView(false);
}
function output(s, isInput, forceFlush = false) {
  if (currentConsoleEl != null && currentConsoleElIsInput !== isInput) {
    flush();
  }
  if (currentConsoleEl == null || currentConsoleElIsInput !== isInput) {
    currentConsoleEl = document.createElement("span");
    currentConsoleEl.className = isInput ? "in" : "out";
    currentConsoleElIsInput = isInput;
    consoleEl.insertBefore(currentConsoleEl, cursorEl);
  }
  outputBuffer.push(s);
  if (forceFlush || isInput || s.endsWith("\n")) {
    flush();
  }
}

function unoutput(isInput) {
  if (
    currentConsoleElIsInput !== isInput ||
    currentConsoleEl.lastChild == null
  ) {
    console.log("not erasing character");
    return;
  }
  currentConsoleEl.lastChild.remove();
}

function startConsole() {
  let inputbuffer = [];

  function load(s) {
    const commands = s.split("\n");
    let newInputBuffer = [];
    if (commands.length > 0) {
      newInputBuffer.push(commands.pop());
    }
    for (const command of commands) {
      output(command, true);
      output(" ", true);
      forth.interpret(inputbuffer.join("") + command);
      inputbuffer = [];
    }
    if (newInputBuffer.length > 0) {
      output(newInputBuffer.join(""), true);
      flush();
    }
    inputbuffer = newInputBuffer;
  }

  document.addEventListener("keydown", (ev) => {
    // console.log("keydown", ev);
    if (ev.key === "Enter") {
      output(" ", true);
      forth.interpret(inputbuffer.join(""));
      inputbuffer = [];
    } else if (ev.key === "Backspace") {
      if (inputbuffer.length > 0) {
        inputbuffer = inputbuffer.slice(0, inputbuffer.length - 1);
        unoutput(true);
      }
    } else if (ev.key.length === 1 && !ev.metaKey && !ev.ctrlKey) {
      output(ev.key, true);
      inputbuffer.push(ev.key);
    } else if (ev.key === "o" && (ev.metaKey || ev.ctrlKey)) {
      if (!window.showOpenFilePicker) {
        window.alert("File loading not supported on this browser");
        return;
      }
      (async () => {
        const [fh] = await window.showOpenFilePicker({
          types: [
            {
              description: "Forth source files",
              accept: {
                "text/plain": [".fs", ".f", ".fth", ".f4th", ".fr"],
              },
            },
          ],
          excludeAcceptAllOption: true,
          multiple: false,
        });
        load(await (await fh.getFile()).text());
      })();
    } else {
      console.log("ignoring key %s", ev.key);
    }
    if (ev.key === " ") {
      ev.preventDefault();
    }
  });

  document.addEventListener("paste", (event) => {
    load(event.clipboardData || window.clipboardData).getData("text");
  });
}

function clearConsole() {
  consoleEl.innerHTML = `<span class='header'><a target='_blank' href='https://github.com/remko/waforth'>WAForth (${version})</a>\n</span><span class="cursor"> </span><input type="text">`;
  inputEl = document.querySelector("input");
  cursorEl = document.querySelector(".cursor");
}

forth.onEmit = withCharacterBuffer((c) => {
  output(c, false);
});

clearConsole();

(async () => {
  output("Loading core ... ", false, true);
  try {
    await forth.load();
    clearConsole();
    startConsole();

    // Parse query string
    const qs = {};
    for (const p of window.location.search
      .substring(window.location.search.indexOf("?") + 1)
      .replace(/\+/, " ")
      .split("&")) {
      const j = p.indexOf("=");
      if (j > 0) {
        qs[decodeURIComponent(p.substring(0, j))] = decodeURIComponent(
          p.substring(j + 1)
        );
      }
    }
    if (qs.p != null) {
      for (const command of qs.p.split("\n")) {
        output(command, true);
        output(" ", true);
        forth.interpret(command);
      }
    }
  } catch (e) {
    console.error(e);
    const errorEl = document.createElement("span");
    errorEl.className = "error";
    errorEl.innerText = "error";
    cursorEl.remove();
    inputEl.remove();
    consoleEl.appendChild(errorEl);
  }
})();
