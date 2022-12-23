import "./wafnb.css";
import * as jsx from "../../thurtle/jsx";
import { runIcon, clearIcon, renderCodeCells } from "./CodeCell";

const { setEnableds, runs, clears } = renderCodeCells();

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
