/* global WAFORTH_VERSION */

import WAForth from "../WAForth";
import sieve from "../../examples/sieve.f";
import "./shell.css";

document.title = "WAForth";
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
function output(s, isInput) {
  if (currentConsoleEl == null || currentConsoleElIsInput !== isInput) {
    currentConsoleEl = document.createElement("span");
    currentConsoleEl.className = isInput ? "in" : "out";
    currentConsoleElIsInput = isInput;
    consoleEl.insertBefore(currentConsoleEl, cursorEl);
  }
  currentConsoleEl.appendChild(document.createTextNode(s));
  document.querySelector(".cursor").scrollIntoView(false);
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
    } else {
      console.log("ignoring key %s", ev.key);
    }
    if (ev.key === " ") {
      ev.preventDefault();
    }
  });

  document.addEventListener("paste", (event) => {
    let paste = (event.clipboardData || window.clipboardData).getData("text");
    const commands = paste.split("\n");
    // console.log("paste", paste, commands);
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
      output(newInputBuffer.join(""));
    }
    inputbuffer = newInputBuffer;
  });
}
function clearConsole() {
  consoleEl.innerHTML = `<span class='header'><a target='_blank' href='https://github.com/remko/waforth'>WAForth (${version})</a>\n</span><span class="cursor"> </span><input type="text">`;
  inputEl = document.querySelector("input");
  cursorEl = document.querySelector(".cursor");
}

forth.onEmit = (c) => {
  output(c, false);
};

clearConsole();

output("Loading core ... ", false);
forth.load().then(
  () => {
    output("ok\nLoading sieve ... ", false);
    forth.interpret(sieve);
    clearConsole();
    startConsole();
  },
  (e) => {
    console.error(e);
    const errorEl = document.createElement("span");
    errorEl.className = "error";
    errorEl.innerText = "error";
    cursorEl.remove();
    inputEl.remove();
    consoleEl.appendChild(errorEl);
  }
);
