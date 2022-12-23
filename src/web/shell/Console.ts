import WAForth, { withCharacterBuffer } from "../waforth";
import "./Console.css";

declare let WAFORTH_VERSION: string;

const version = typeof WAFORTH_VERSION !== "undefined" ? WAFORTH_VERSION : "";

export function renderConsole(parentEl: HTMLElement) {
  const forth = new WAForth();

  const consoleEl = document.createElement("pre");
  consoleEl.className = "Console";
  parentEl.appendChild(consoleEl);

  let inputEl: HTMLElement;
  let cursorEl: HTMLElement;

  consoleEl.addEventListener("click", () => {
    inputEl.style.visibility = "visible";
    inputEl.focus();
    inputEl.style.visibility = "hidden";
  });

  let currentConsoleEl: HTMLElement;
  let currentConsoleElIsInput = false;
  let outputBuffer: string[] = [];
  function flush() {
    if (outputBuffer.length == 0) {
      return;
    }
    currentConsoleEl.appendChild(
      document.createTextNode(outputBuffer.join(""))
    );
    outputBuffer = [];
    parentEl.querySelector(".cursor")!.scrollIntoView(false);
  }
  function output(s: string, isInput: boolean, forceFlush = false) {
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

  function unoutput(isInput: boolean) {
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
    let inputbuffer: string[] = [];

    function load(s: string) {
      const commands = s.split("\n");
      const newInputBuffer: string[] = [];
      if (commands.length > 0) {
        newInputBuffer.push(commands.pop()!);
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

    parentEl.addEventListener("keydown", (ev) => {
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
        if (!(window as any).showOpenFilePicker) {
          window.alert("File loading not supported on this browser");
          return;
        }
        (async () => {
          const [fh] = await (window as any).showOpenFilePicker({
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

    parentEl.addEventListener("paste", (event) => {
      load(
        (event.clipboardData || (window as any).clipboardData).getData("text")
      );
    });
  }

  function clearConsole() {
    consoleEl.innerHTML = `<span class='header'><a target='_blank' href='https://github.com/remko/waforth'>WAForth${
      version != null ? ` (${version})` : ""
    }</a>\n</span><span class="cursor"> </span><input type="text">`;
    inputEl = parentEl.querySelector("input")!;
    cursorEl = parentEl.querySelector(".cursor")!;
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
      const qs: Record<string, string> = {};
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
      cursorEl!.remove();
      inputEl!.remove();
      consoleEl.appendChild(errorEl);
    }
  })();
}
