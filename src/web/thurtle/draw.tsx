import * as jsx from "./jsx";
import WAForth from "waforth";
import thurtleFS from "./thurtle.fs";
import turtle from "./turtle.svg";

const padding = 0.05;

enum PenState {
  Up = 0,
  Down = 1,
}

type Path = {
  strokeWidth?: number;
  d: string[];
};

export default async function draw({
  program,
  drawEl,
  outputEl,
  showTurtle = true,
}: {
  program?: string;
  drawEl: SVGSVGElement;
  outputEl?: HTMLElement;
  showTurtle?: boolean;
}) {
  // Initialize state
  let rotation = 270;
  const position = { x: 0, y: 0 };
  const boundingBox = { minX: 0, minY: 0, maxX: 0, maxY: 0 };
  let pen = PenState.Down;
  let visible = true;
  const paths: Array<Path> = [{ d: [`M${position.x} ${position.y}`] }];

  function updatePosition(x: number, y: number) {
    position.x = x;
    position.y = y;
    if (x < boundingBox.minX) {
      boundingBox.minX = x;
    }
    if (x > boundingBox.maxX) {
      boundingBox.maxX = x;
    }
    if (y < boundingBox.minY) {
      boundingBox.minY = y;
    }
    if (y > boundingBox.maxY) {
      boundingBox.maxY = y;
    }
  }

  // Run program
  if (program != null) {
    const forth = new WAForth();
    await forth.load();

    forth.bind("forward", (stack) => {
      const d = stack.pop();
      const dx = d * Math.cos((rotation * Math.PI) / 180.0);
      const dy = d * Math.sin((rotation * Math.PI) / 180.0);
      paths[paths.length - 1].d.push(
        [pen === PenState.Down ? "l" : "m", dx, dy].join(" ")
      );
      updatePosition(position.x + dx, position.y + dy);
    });

    forth.bind("rotate", (stack) => {
      rotation = rotation - stack.pop();
    });

    forth.bind("pen", (stack) => {
      pen = stack.pop();
    });

    forth.bind("turtle", (stack) => {
      visible = stack.pop() !== 0;
    });

    forth.bind("setpensize", (stack) => {
      const s = stack.pop();
      paths.push({ d: [`M ${position.x} ${position.y}`], strokeWidth: s });
    });

    forth.bind("setxy", (stack) => {
      const y = stack.pop();
      const x = stack.pop();
      paths[paths.length - 1].d.push(
        [pen === PenState.Down ? "l" : "M", x, y].join(" ")
      );
      updatePosition(x, y);
    });

    forth.bind("setheading", (stack) => {
      rotation = -90 - stack.pop();
    });

    forth.interpret(thurtleFS);
    if (outputEl != null) {
      forth.onEmit = (c) => {
        outputEl.appendChild(document.createTextNode(c));
        if (c === "\n") {
          outputEl.scrollTop = outputEl.scrollHeight;
        }
      };
    }
    forth.interpret(program, true);
  }

  // Draw
  drawEl.innerHTML = "";
  const pathsEl = (
    <g fill-opacity="0" stroke="#000" xmlns="http://www.w3.org/2000/svg"></g>
  );
  const turtleEl = (
    <image
      xmlns="http://www.w3.org/2000/svg"
      data-hook="turtle"
      width="50"
      height="50"
      href={turtle}
    />
  );

  pathsEl.innerHTML = "";
  for (const path of paths) {
    const pathEl = (
      <path
        xmlns="http://www.w3.org/2000/svg"
        d={path.d.join(" ")}
        stroke-width={(path.strokeWidth ?? 5) + ""}
      />
    );
    pathsEl.appendChild(pathEl);
  }

  turtleEl.style.display = visible ? "block" : "none";
  turtleEl.setAttribute(
    "transform",
    `rotate(${rotation} ${position.x} ${position.y}) translate(${
      position.x - 25
    } ${position.y - 25})`
  );

  const width = boundingBox.maxX - boundingBox.minX;
  const height = boundingBox.maxY - boundingBox.minY;
  if (width == 0 || height == 0) {
    drawEl.setAttribute("viewBox", "-500 -500 1000 1000");
  } else {
    const paddingX = width * padding;
    const paddingY = height * padding;
    drawEl.setAttribute(
      "viewBox",
      [
        Math.floor(boundingBox.minX - paddingX),
        Math.floor(boundingBox.minY - paddingY),
        Math.ceil(width + 2 * paddingX),
        Math.ceil(height + 2 * paddingY),
      ].join(" ")
    );
  }

  drawEl.appendChild(pathsEl);
  if (showTurtle) {
    drawEl.appendChild(turtleEl);
  }
}
