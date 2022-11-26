import "./wafnb.css";
import Editor from "../../thurtle/Editor";
import * as jsx from "../../thurtle/jsx";
import draw from "../../thurtle/draw";
import { isSuccess, withLineBuffer } from "waforth";

const runIcon = () => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width="16"
    height="16"
    fill="currentColor"
    class="bi"
    viewBox="0 0 16 16"
  >
    <path
      xmlns="http://www.w3.org/2000/svg"
      d="M10.804 8 5 4.633v6.734L10.804 8zm.792-.696a.802.802 0 0 1 0 1.392l-6.363 3.692C4.713 12.69 4 12.345 4 11.692V4.308c0-.653.713-.998 1.233-.696l6.363 3.692z"
    />
  </svg>
);

const clearIcon = () => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width="16"
    height="16"
    fill="currentColor"
    class="bi"
    viewBox="0 0 16 16"
  >
    <path
      xmlns="http://www.w3.org/2000/svg"
      d="M8.086 2.207a2 2 0 0 1 2.828 0l3.879 3.879a2 2 0 0 1 0 2.828l-5.5 5.5A2 2 0 0 1 7.879 15H5.12a2 2 0 0 1-1.414-.586l-2.5-2.5a2 2 0 0 1 0-2.828l6.879-6.879zm2.121.707a1 1 0 0 0-1.414 0L4.16 7.547l5.293 5.293 4.633-4.633a1 1 0 0 0 0-1.414l-3.879-3.879zM8.746 13.547 3.453 8.254 1.914 9.793a1 1 0 0 0 0 1.414l2.5 2.5a1 1 0 0 0 .707.293H7.88a1 1 0 0 0 .707-.293l.16-.16z"
    />
  </svg>
);

const runs: Array<() => Promise<void>> = [];
const clears: Array<() => void> = [];
const setEnableds: Array<(v: boolean) => void> = [];

for (const n of document.querySelectorAll("[data-hook=code-cell")) {
  n.className = "code-cell";
  const program = n.textContent ?? "";

  const editor = new Editor(true);
  editor.setValue(program);
  n.innerHTML = "";
  n.appendChild(editor.el);

  const outputEl = <div class="output" />;
  outputEl.style.display = "none";
  n.appendChild(outputEl);

  const setEnabled = (v: boolean) => {
    runEl.disabled = !v;
  };
  setEnableds.push(setEnabled);

  const clear = () => {
    outputEl.style.display = "none";
    outputEl.innerHTML = "";
    clearEl.style.display = "none";
    editor.el.style.borderColor = "#ced4da";
  };
  clears.push(clear);

  const run = async () => {
    setEnabled(false);
    try {
      clear();
      const worldEl = <svg class="world" xmlns="http://www.w3.org/2000/svg" />;
      const consoleEl: HTMLPreElement = <pre class="console" />;
      const result = await draw({
        program: editor.getValue(),
        drawEl: worldEl,
        onEmit: (c: string) => {
          consoleEl.appendChild(document.createTextNode(c));
        },
        jsx,
      });
      if (!result.isEmpty) {
        outputEl.appendChild(worldEl);
        outputEl.style.display = "flex";
      }
      if (consoleEl.childNodes.length > 0) {
        outputEl.appendChild(consoleEl);
        outputEl.style.display = "flex";
      }
      clearEl.style.display = "block";
      editor.el.style.borderColor = isSuccess(result.result)
        ? "rgb(60, 166, 60)"
        : "rgb(208, 49, 49)";
    } catch (e) {
      alert((e as any).message);
    } finally {
      setEnabled(true);
    }
  };
  runs.push(run);
  const runEl = (
    <button title="Run" class="toolbutton" onclick={run}>
      {runIcon()}
    </button>
  );
  const clearEl = (
    <button title="Clear" class="toolbutton" onclick={clear}>
      {clearIcon()}
    </button>
  );
  clearEl.style.display = "none";
  n.insertBefore(
    <div class="controls">
      {runEl}
      {clearEl}
    </div>,
    editor.el
  );
}

function setAllEnabled(v: boolean) {
  for (const setEnabled of setEnableds) {
    setEnabled(v);
  }
  runAllButtonEl.disabled = !v;
  clearAllButtonEl.disabled = !v;
}
async function runAll() {
  setAllEnabled(false);
  try {
    for (const run of runs) {
      await run();
    }
  } catch (e) {
    // do nothing
  } finally {
    setAllEnabled(true);
  }
}

async function clearAll() {
  for (const clear of clears) {
    clear();
  }
}

const contentEl = document.querySelector("[data-hook=content]")!;
const runAllButtonEl = (
  <button title="Run all" class="toolbutton" onclick={runAll}>
    {runIcon()}
  </button>
);
const clearAllButtonEl = (
  <button title="Clear all" class="toolbutton" onclick={clearAll}>
    {clearIcon()}
  </button>
);
const controlsEl = (
  <div class="all-controls">
    {runAllButtonEl}
    {clearAllButtonEl}
  </div>
);
contentEl.insertBefore(controlsEl, contentEl.firstElementChild);
