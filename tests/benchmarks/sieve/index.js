import WAForth from "../../../src/shell/WAForth";
import sieve from "../../../src/shell/sieve";

const ITERATIONS = 3;
const LIMIT = 50000000;

const forth = new WAForth();
let outputBuffer = [];
forth.onEmit = c => {
  outputBuffer.push(String.fromCharCode(c));
};
document.body.innerHTML = "Loading...";
forth.start().then(
  () => {
    document.body.innerHTML = "<div>Running...</div>";
    forth.run(sieve);
    let i = 0;
    const run = () => {
      if (i < ITERATIONS) {
        outputBuffer = [];
        const t1 = performance.now();
        outputBuffer = [77, 88];
        forth.run(`${LIMIT} sieve`);
        const t2 = performance.now();
        document.body.innerHTML =
          document.body.innerHTML +
          `<div><pre style='display: inline-block; margin: 0; margin-right: 1rem'>${outputBuffer.join(
            ""
          )}</pre><span>${(t2 - t1) / 1000.0}</span></div>`;
        i += 1;
        window.setTimeout(run, 0);
      } else {
        document.body.innerHTML = document.body.innerHTML + "<div>Done</div>";
      }
    };
    window.setTimeout(run, 10);
  },
  err => {
    console.error(err);
    document.body.innerHTML = "Error";
  }
);
