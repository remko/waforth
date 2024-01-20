/////////////////////////////////////////////////////////////////////////
// Query parameters:
// `p`: Base64-encoded program
// `pn`: Program name. If `p` is not provided, looks up builtin example
// `ar`: Auto-run program
// `sn`: Show navbar (default: 1)
/////////////////////////////////////////////////////////////////////////

import * as jsx from "./jsx";
import "./thurtle.css";
import logo from "../../../doc/logo.svg";
import {
  deleteProgram,
  getProgram,
  listPrograms,
  saveProgram,
} from "./programs";
import Editor from "./Editor";
import { saveAs } from "file-saver";
import draw from "./draw";

declare let bootstrap: any;

function parseQS(sqs = window.location.search) {
  const qs: Record<string, string> = {};
  const sqss = sqs
    .substring(sqs.indexOf("?") + 1)
    .replace(/\+/, " ")
    .split("&");
  for (const p of sqss) {
    const j = p.indexOf("=");
    if (j > 0) {
      qs[decodeURIComponent(p.substring(0, j))] = decodeURIComponent(
        p.substring(j + 1)
      );
    }
  }
  return qs;
}

const qs = parseQS();

function About() {
  return (
    <>
      Logo-like Forth Turtle graphics (powered by{" "}
      <a href="https://github.com/remko/waforth">WAForth</a>)
    </>
  );
}

const editor = new Editor();

const rootEl = (
  <div class={"root" + (qs.sn === "0" ? " no-nav" : "")}>
    <nav class="navbar navbar-light bg-light">
      <div class="container-fluid">
        <a class="navbar-brand" href="/thurtle">
          <img
            src={logo}
            width={30}
            height={24}
            class="d-inline-block align-text-top"
          />
          Thurtle
        </a>

        <span class="navbar-text d-none d-sm-block">
          <About />
        </span>

        <div>
          <a
            role="button"
            class="text-reset"
            href="https://github.com/remko/waforth/tree/master/src/web/thurtle"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="16"
              height="16"
              fill="currentColor"
              class="bi ms-2"
              viewBox="0 0 16 16"
            >
              <path
                xmlns="http://www.w3.org/2000/svg"
                d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.012 8.012 0 0 0 16 8c0-4.42-3.58-8-8-8z"
              />
            </svg>
          </a>
          <a role="button" data-bs-toggle="modal" data-bs-target="#helpModal">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="16"
              height="16"
              fill="currentColor"
              class="bi ms-2"
              viewBox="0 0 16 16"
            >
              <path
                xmlns="http://www.w3.org/2000/svg"
                d="M16 8A8 8 0 1 1 0 8a8 8 0 0 1 16 0zM5.496 6.033h.825c.138 0 .248-.113.266-.25.09-.656.54-1.134 1.342-1.134.686 0 1.314.343 1.314 1.168 0 .635-.374.927-.965 1.371-.673.489-1.206 1.06-1.168 1.987l.003.217a.25.25 0 0 0 .25.246h.811a.25.25 0 0 0 .25-.25v-.105c0-.718.273-.927 1.01-1.486.609-.463 1.244-.977 1.244-2.056 0-1.511-1.276-2.241-2.673-2.241-1.267 0-2.655.59-2.75 2.286a.237.237 0 0 0 .241.247zm2.325 6.443c.61 0 1.029-.394 1.029-.927 0-.552-.42-.94-1.029-.94-.584 0-1.009.388-1.009.94 0 .533.425.927 1.01.927z"
              />
            </svg>
          </a>
        </div>
      </div>
    </nav>
    <div class="main d-flex flex-column p-2">
      <div class="d-flex flex-row flex-grow-1 h-100">
        <div class="left-pane d-flex flex-column">
          <div class="d-flex flex-row flex-wrap flex-md-nowrap pb-2">
            <select class="form-select" data-hook="examples"></select>
            <div class="ms-auto me-auto ms-md-2 me-md-0 mt-1 mt-md-0">
              <div class="btn-group w-xs-100">
                <button
                  class="btn btn-primary"
                  aria-label="Run"
                  data-hook="run"
                  onclick={run}
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="16"
                    height="16"
                    fill="currentColor"
                    class="bi bi-play-fill"
                    viewBox="0 0 16 16"
                  >
                    <path
                      xmlns="http://www.w3.org/2000/svg"
                      d="m11.596 8.697-6.363 3.692c-.54.313-1.233-.066-1.233-.697V4.308c0-.63.692-1.01 1.233-.696l6.363 3.692a.802.802 0 0 1 0 1.393z"
                    />
                  </svg>
                </button>
                <button
                  type="button"
                  class="btn btn-light border"
                  data-hook="save-btn"
                  aria-label="Save"
                  onclick={save}
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    width="16"
                    height="16"
                    fill="currentColor"
                    class="bi bi-hdd"
                    viewBox="0 0 16 16"
                  >
                    <path
                      xmlns="http://www.w3.org/2000/svg"
                      d="M4.5 11a.5.5 0 1 0 0-1 .5.5 0 0 0 0 1zM3 10.5a.5.5 0 1 1-1 0 .5.5 0 0 1 1 0z"
                    />
                    <path
                      xmlns="http://www.w3.org/2000/svg"
                      d="M16 11a2 2 0 0 1-2 2H2a2 2 0 0 1-2-2V9.51c0-.418.105-.83.305-1.197l2.472-4.531A1.5 1.5 0 0 1 4.094 3h7.812a1.5 1.5 0 0 1 1.317.782l2.472 4.53c.2.368.305.78.305 1.198V11zM3.655 4.26 1.592 8.043C1.724 8.014 1.86 8 2 8h12c.14 0 .276.014.408.042L12.345 4.26a.5.5 0 0 0-.439-.26H4.094a.5.5 0 0 0-.44.26zM1 10v1a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-1a1 1 0 0 0-1-1H2a1 1 0 0 0-1 1z"
                    />
                  </svg>
                </button>
                <button
                  type="button"
                  class="btn btn-light dropdown-toggle dropdown-toggle-split border"
                  data-bs-toggle="dropdown"
                  aria-expanded="false"
                >
                  <span class="visually-hidden">Toggle Dropdown</span>
                </button>
                <ul class="dropdown-menu">
                  <li>
                    <a
                      class="dropdown-item"
                      href="#"
                      onclick={(ev) => save(ev, true)}
                    >
                      Save as
                    </a>
                  </li>
                  <li>
                    <a
                      class="dropdown-item"
                      href="#"
                      data-hook="delete-action"
                      onclick={del}
                    >
                      Delete
                    </a>
                  </li>
                  <li class="dropdown-divider"></li>
                  <li>
                    <a class="dropdown-item" href="#" onclick={share}>
                      Share
                    </a>
                  </li>
                  <li>
                    <a class="dropdown-item" href="#" onclick={downloadSVG}>
                      Download as SVG
                    </a>
                  </li>
                  <li>
                    <a class="dropdown-item" href="#" onclick={downloadPNG}>
                      Download as PNG
                    </a>
                  </li>
                </ul>
              </div>
            </div>
          </div>
          {editor.el}
        </div>
        <div class="d-flex flex-column ms-2 right-pane">
          <svg
            class="world"
            xmlns="http://www.w3.org/2000/svg"
            data-hook="world"
          />
          <form data-hook="output-container" style="display: none">
            <div class="form-group mt-2">
              <label>Output</label>
              <pre
                class="mb-0 border rounded px-2 py-1 output"
                data-hook="output"
              ></pre>
            </div>
          </form>
        </div>
      </div>
      {qs.sn !== "0" ? (
        <div class="container mt-2 text-muted d-sm-none">
          <p>
            <About />
          </p>
        </div>
      ) : null}
    </div>
    <div
      class="modal fade"
      id="helpModal"
      tabIndex={-1}
      aria-labelledby="helpModalLabel"
      aria-hidden="true"
    >
      <div class="modal-dialog modal-xl">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title" id="helpModalLabel">
              Help
            </h5>
            <button
              type="button"
              class="btn-close"
              data-bs-dismiss="modal"
              aria-label="Close"
            ></button>
          </div>
          <div class="modal-body">
            <p>
              The following words for moving the turtle are available:
              <ul>
                <li>
                  <code>FORWARD ( n -- )</code>: Move forward by <code>n</code>.
                </li>
                <li>
                  <code>BACKWARD ( n -- )</code>: Move backward by{" "}
                  <code>n</code>.
                </li>
                <li>
                  <code>LEFT ( n -- )</code>: Turn left by <code>n</code>{" "}
                  degrees.
                </li>
                <li>
                  <code>RIGHT ( n -- )</code>: Turn right by <code>n</code>{" "}
                  degrees.
                </li>
                <li>
                  <code>SETXY ( n1 n2 -- )</code>: Move to position{" "}
                  <code>n1,n2</code>.
                </li>
                <li>
                  <code>SETHEADING ( n -- )</code>: Set heading <code>n</code>{" "}
                  degrees clockwise from Y axis.
                </li>
                <li>
                  <code>PENUP ( -- )</code>: Disable drawing while moving.
                </li>
                <li>
                  <code>PENDOWN ( -- )</code>: Enable drawing while moving.
                </li>
                <li>
                  <code>SETPENSIZE ( n -- )</code>: Set the width of the drawed
                  strokes to <code>n</code> (default: 5).
                </li>
                <li>
                  <code>HIDETURTLE ( -- )</code>: Hide the turtle.
                </li>
                <li>
                  <code>SHOWTURTLE ( -- )</code>: Show the turtle.
                </li>
              </ul>
            </p>
          </div>
          <div class="modal-footer">
            <button
              type="button"
              class="btn btn-secondary"
              data-bs-dismiss="modal"
            >
              Close
            </button>
          </div>
        </div>
      </div>
    </div>
    <div class="modal" tabIndex={-1} data-hook="share-modal">
      <div class="modal-dialog modal-lg">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title">
              Share '<span data-hook="title"></span>'
            </h5>
            <button
              type="button"
              class="btn-close"
              data-bs-dismiss="modal"
              aria-label="Close"
            ></button>
          </div>
          <div class="modal-body">
            <p>Share URL</p>
            <input
              data-hook="url"
              onClick={selectShareURL}
              type="text"
              readOnly={true}
              class="form-control"
            />
          </div>
          <div class="modal-footer">
            <button
              type="button"
              class="btn btn-secondary"
              data-bs-dismiss="modal"
            >
              Close
            </button>
          </div>
        </div>
      </div>
    </div>

    <div data-hook="saving-modal" class="modal" tabIndex={-1} role="dialog">
      <div class="modal-dialog" role="document">
        <div class="modal-content">
          <div class="modal-body text-center">
            <p>Saving as PNG ...</p>
            <div class="spinner-border" role="status">
              <span class="visually-hidden">Loading...</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
);
document.body.appendChild(rootEl);

const runButtonEl = rootEl.querySelector(
  "button[data-hook=run]"
)! as HTMLButtonElement;
const programsEl = rootEl.querySelector(
  "[data-hook=examples]"
)! as HTMLSelectElement;
const outputContainerEl = rootEl.querySelector(
  "[data-hook=output-container]"
) as HTMLFormElement;
const outputEl = rootEl.querySelector(
  "pre[data-hook=output]"
) as HTMLPreElement;
const deleteActionEl = rootEl.querySelector(
  "[data-hook=delete-action]"
) as HTMLAnchorElement;
const shareModalEl = rootEl.querySelector("[data-hook=share-modal]");
const shareModal = new bootstrap.Modal(shareModalEl);
const shareModalTitleEl = rootEl.querySelector(
  "[data-hook=share-modal] [data-hook=title]"
) as HTMLSpanElement;
const savingModal = new bootstrap.Modal(
  rootEl.querySelector("[data-hook=saving-modal]")
);
const shareModalURLEl = rootEl.querySelector(
  "[data-hook=share-modal] [data-hook=url]"
) as HTMLInputElement;
const worldEl = rootEl.querySelector("[data-hook=world]") as SVGSVGElement;

//////////////////////////////////////////////////////////////////////////////////////////
// Programs
//////////////////////////////////////////////////////////////////////////////////////////

const DEFAULT_PROGRAM = "Plant";

function loadProgram(name: string) {
  const program = getProgram(name)!;
  editor.setValue(program.program);
  if (program.isExample) {
    deleteActionEl.classList.add("disabled");
  } else {
    deleteActionEl.classList.remove("disabled");
  }
  programsEl.value = name;
  document.title = name + " - Thurtle";
}

function loadPrograms() {
  programsEl.innerText = "";
  for (const ex of listPrograms().filter((p) => !p.isExample)) {
    programsEl.appendChild(<option value={ex.name}>{ex.name}</option>);
  }
  programsEl.appendChild(<option disabled={true}>Examples</option>);
  for (const ex of listPrograms().filter((p) => p.isExample)) {
    programsEl.appendChild(<option value={ex.name}>{ex.name}</option>);
  }
}

function save(ev: MouseEvent, forceSaveAs?: boolean) {
  ev.preventDefault();
  let name = programsEl.value;
  const program = getProgram(name);
  if (program?.isExample || forceSaveAs) {
    const title = program?.isExample ? name + " (Copy)" : name;
    const newName = window.prompt("Program name", title);
    if (newName == null) {
      return;
    }
    if (getProgram(newName)?.isExample) {
      window.alert(`Cannot save as example '${name}'`);
      return;
    }
    name = newName;
  }
  if (saveProgram(name, editor.getValue())) {
    loadPrograms();
    loadProgram(name);
  }
}

function del(ev: MouseEvent) {
  ev.preventDefault();
  if (
    !window.confirm(`Are you sure you want to delete '${programsEl.value}'?`)
  ) {
    return;
  }
  deleteProgram(programsEl.value);
  loadPrograms();
  loadProgram(DEFAULT_PROGRAM);
}

async function getSVG(): Promise<{
  data: string;
  width: number;
  height: number;
}> {
  const svgEl = <svg xmlns="http://www.w3.org/2000/svg" />;
  await draw({
    program: editor.getValue(),
    drawEl: svgEl,
    showTurtle: false,
    jsx,
  });
  const viewBox = svgEl.getAttribute("viewBox")!.split(" ");
  svgEl.setAttribute("width", parseInt(viewBox[2]) + "");
  svgEl.setAttribute("height", parseInt(viewBox[3]) + "");
  return {
    width: parseInt(svgEl.getAttribute("width")!),
    height: parseInt(svgEl.getAttribute("height")!),
    data: svgEl.outerHTML,
  };
}

async function downloadSVG(ev: MouseEvent) {
  ev.preventDefault();
  const blob = new Blob([(await getSVG()).data], { type: "image/svg+xml" });
  saveAs(blob, programsEl.value + ".svg");
}

async function downloadPNG(ev: MouseEvent) {
  ev.preventDefault();
  savingModal.show();
  const svg = await getSVG();
  const img = document.createElement("img");
  img.style.display = "none";
  document.body.appendChild(img);
  try {
    const dataURL = await new Promise<string>((resolve, reject) => {
      img.onerror = (e) => {
        reject(e);
      };
      img.onload = () => {
        const canvas = document.createElement("canvas");
        canvas.width = svg.width;
        canvas.height = svg.height;
        const ctx = canvas.getContext("2d")!;
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        resolve(canvas.toDataURL("image/png"));
      };
      img.src = "data:image/svg+xml;base64," + btoa(svg.data);
    });
    const blob = await (await fetch(dataURL)).blob();
    saveAs(blob, programsEl.value + ".png");
  } catch (e) {
    console.error(e);
  } finally {
    img.remove();
    savingModal.hide();
  }
}

function share(ev: MouseEvent) {
  ev.preventDefault();
  shareModalTitleEl.innerText = programsEl.value;
  shareModalURLEl.value = `${window.location.protocol}//${
    window.location.host
  }${window.location.pathname}?pn=${encodeURIComponent(
    programsEl.value
  )}&p=${encodeURIComponent(btoa(editor.getValue()))}&ar=1`;
  shareModal.show();
}

function selectShareURL() {
  shareModalURLEl.focus();
  shareModalURLEl.setSelectionRange(0, 9999);
  shareModalURLEl.scrollLeft = 0;
}

shareModalEl.addEventListener("shown.bs.modal", () => {
  selectShareURL();
});

programsEl.addEventListener("change", (ev) => {
  loadProgram((ev.target! as HTMLSelectElement).value);
});

document.addEventListener("keydown", (ev) => {
  if (ev.key == "Enter" && (ev.metaKey || ev.ctrlKey)) {
    run();
  }
});

//////////////////////////////////////////////////////////////////////////////////////////

const output = (c: string) => {
  outputContainerEl.style.display = "block";
  outputEl.appendChild(document.createTextNode(c));
  outputEl.scrollTop = outputEl.scrollHeight;
};

async function run() {
  try {
    outputContainerEl.style.display = "none";
    outputEl.innerHTML = "";
    runButtonEl.disabled = true;
    await draw({
      program: editor.getValue(),
      drawEl: worldEl,
      onEmit: output,
      jsx,
    });
    editor.focus();
  } catch (e) {
    console.error(e);
  } finally {
    runButtonEl.disabled = false;
  }
}

async function reset() {
  await draw({ drawEl: worldEl, onEmit: output, jsx });
}

/////////////////////////////////////////////////////////////////////////

if (qs.p) {
  saveProgram(qs.pn ?? "", atob(qs.p), true);
  loadPrograms();
  loadProgram(qs.pn);
} else {
  loadPrograms();
  loadProgram(qs.pn ?? DEFAULT_PROGRAM);
}

if (qs.ar) {
  run();
} else {
  reset();
}
