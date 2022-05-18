import * as jsx from "./jsx";
import WAForth from "waforth";
import "./thurtle.css";
import turtle from "./turtle.svg";
import logo from "../../../doc/logo.svg";
import thurtleFS from "./thurtle.fs";
import examples from "./examples";
import Editor from "./Editor";

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
  <div class="root">
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
      <div class="d-flex flex-row flex-grow-1">
        <div class="left-pane d-flex flex-column">
          <select class="form-select mb-2" data-hook="examples"></select>
          {editor.el}
          <button data-hook="run" class="btn btn-primary mt-2">
            Run
          </button>
        </div>
        <div class="d-flex flex-column ms-3 right-pane">
          <svg
            class="world"
            viewBox="0 0 1000 1000"
            xmlns="http://www.w3.org/2000/svg"
          >
            <g
              xmlns="http://www.w3.org/2000/svg"
              transform="translate(500 500)"
            >
              <g xmlns="http://www.w3.org/2000/svg" id="paths"></g>
              <image
                xmlns="http://www.w3.org/2000/svg"
                id="turtle"
                width="50"
                height="50"
                href={turtle}
              />
            </g>
          </svg>
          <form>
            <div class="form-group mt-3">
              <label>Output</label>
              <pre class="output" data-hook="output"></pre>
            </div>
          </form>
        </div>
      </div>
      <div class="container mt-2 text-muted d-sm-none">
        <p>
          <About />
        </p>
      </div>
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
  </div>
);
document.body.appendChild(rootEl);

const turtleEl = document.getElementById("turtle")!;
let pathEl: SVGPathElement;
const patshEl = document.getElementById("paths")!;
const runButtonEl = rootEl.querySelector(
  "button[data-hook=run]"
)! as HTMLButtonElement;
const examplesEl = rootEl.querySelector(
  "[data-hook=examples]"
)! as HTMLSelectElement;
const outputEl = rootEl.querySelector(
  "pre[data-hook=output]"
) as HTMLPreElement;

enum PenState {
  Up = 0,
  Down = 1,
}

let rotation = 0;
let position = { x: 0, y: 0 };
let pen = PenState.Down;
let visible = true;

function newPathEl() {
  pathEl = (
    <path xmlns="http://www.w3.org/2000/svg" stroke-width="5" d="M 0 0" />
  );
  patshEl.appendChild(pathEl);
}

function reset() {
  position.x = position.y = 0;
  rotation = 270;
  pen = PenState.Down;
  patshEl.innerHTML = "";
  newPathEl();
  outputEl.innerHTML = "";
  updateTurtle();
}

function updateTurtle() {
  turtleEl.style.display = visible ? "block" : "none";
  turtleEl.setAttribute(
    "transform",
    `rotate(${rotation} ${position.x} ${position.y}) translate(${
      position.x - 25
    } ${position.y - 25})`
  );
}

function rotate(deg: number) {
  rotation = rotation + deg;
  updateTurtle();
}

function setRotation(deg: number) {
  rotation = deg;
  updateTurtle();
}

function forward(d: number) {
  const dx = d * Math.cos((rotation * Math.PI) / 180.0);
  const dy = d * Math.sin((rotation * Math.PI) / 180.0);
  pathEl.setAttribute(
    "d",
    pathEl.getAttribute("d")! +
      " " +
      [pen === PenState.Down ? "l" : "m", dx, dy].join(" ")
  );

  position.x += dx;
  position.y += dy;
  updateTurtle();
}

function setXY(x: number, y: number) {
  pathEl.setAttribute(
    "d",
    pathEl.getAttribute("d")! +
      " " +
      [pen === PenState.Down ? "l" : "M", x, y].join(" ")
  );

  position.x = x;
  position.y = y;
  updateTurtle();
}

function setPen(s: PenState) {
  pen = s;
}

function setPenSize(s: number) {
  newPathEl();
  pathEl.setAttribute("stroke-width", s + "");
}

function setVisible(b: boolean) {
  visible = b;
  updateTurtle();
}

function loadExample(name: string) {
  editor.setValue(examples.find((e) => e.name === name)!.program);
  examplesEl.value = name;
}

for (const ex of examples) {
  examplesEl.appendChild(<option value={ex.name}>{ex.name}</option>);
}
examplesEl.addEventListener("change", (ev) => {
  loadExample((ev.target! as HTMLSelectElement).value);
});

async function run() {
  try {
    runButtonEl.disabled = true;
    reset();

    const forth = new WAForth();
    await forth.load();
    forth.bind("forward", (stack) => {
      forward(stack.pop());
    });
    forth.bind("rotate", (stack) => {
      rotate(-stack.pop());
    });
    forth.bind("pen", (stack) => {
      setPen(stack.pop());
    });
    forth.bind("turtle", (stack) => {
      setVisible(stack.pop() != 0);
    });
    forth.bind("setpensize", (stack) => {
      setPenSize(stack.pop());
    });
    forth.bind("setxy", (stack) => {
      const y = stack.pop();
      const x = stack.pop();
      setXY(x, -y);
    });
    forth.bind("setheading", (stack) => {
      setRotation(-90 - stack.pop());
    });
    forth.interpret(thurtleFS);
    forth.onEmit = (c) => outputEl.appendChild(document.createTextNode(c));
    forth.interpret(editor.getValue());
    editor.focus();
  } catch (e) {
    console.error(e);
  } finally {
    runButtonEl.disabled = false;
  }
}

runButtonEl.addEventListener("click", () => run());
document.addEventListener("keydown", (ev) => {
  if (ev.key == "Enter" && (ev.metaKey || ev.ctrlKey)) {
    run();
  }
});

reset();

loadExample(examples[4].name);
