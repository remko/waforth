import WAForth from "../WAForth";
import sieve from "../sieve";
import "./shell.css";

document.title = "WAForth";

const forth = new WAForth();

const consoleEl = document.createElement("pre");
consoleEl.className = "console";
document.body.appendChild(consoleEl);

let currentConsoleEl;
let currentConsoleElIsInput = false;
function output(s, isInput) {
  if (currentConsoleEl == null || currentConsoleElIsInput !== isInput) {
    currentConsoleEl = document.createElement("span");
    currentConsoleEl.className = isInput ? "in" : "out";
    currentConsoleElIsInput = isInput;
    consoleEl.insertBefore(currentConsoleEl, consoleEl.lastChild);
  }
  currentConsoleEl.appendChild(document.createTextNode(s));
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
  document.addEventListener("keypress", (ev) => {
    // console.log(ev);
    if (ev.key === "Enter") {
      output(" ", true);
      forth.run(inputbuffer.join(""));
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
      forth.run(inputbuffer.join("") + command);
      inputbuffer = [];
    }
    if (newInputBuffer.length > 0) {
      output(newInputBuffer.join(""));
    }
    inputbuffer = newInputBuffer;
  });
}
function clearConsole() {
  consoleEl.innerHTML =
    "<span class='header'><a target='_blank' href='https://github.com/remko/waforth'>WAForth</a>\n</span><span class=\"cursor\"> </span>";
}

forth.onEmit = (c) => {
  output(String.fromCharCode(c), false);
};

clearConsole();

output("Loading core ... ", false);
forth.start().then(
  () => {
    output("ok\nLoading sieve ... ", false);
    forth.run(sieve);
    clearConsole();
    startConsole();
  },
  () => {
    const errorEl = document.createElement("span");
    errorEl.className = "error";
    errorEl.innerText = "error";
    consoleEl.lastChild.remove();
    consoleEl.appendChild(errorEl);
  }
);
