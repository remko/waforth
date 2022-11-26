import React from "react";
import { createRoot } from "react-dom/client";
import WAForth, { withCharacterBuffer } from "../waforth";
import sieve from "../../examples/sieve.f";
import sieveWasmModule from "./sieve/sieve.wat";
import sieveJS from "./sieve/sieve.js";
import update from "immutability-helper";
import "./benchmarks.css";

// eslint-disable-next-line no-unused-vars, @typescript-eslint/no-unused-vars
const jsx = React;

////////////////////////////////////////////////////////////////////////////////
// Initial setup
////////////////////////////////////////////////////////////////////////////////

const setup = [];

const forth = new WAForth();
let outputBuffer = [];
forth.onEmit = withCharacterBuffer((c) => {
  outputBuffer.push(c);
});
setup.push(
  forth.load().then(() => {
    forth.interpret(sieve);
  })
);

let sieveWasm;
setup.push(
  WebAssembly.instantiate(sieveWasmModule, {
    js: {
      print: (x) => console.log(x),
    },
  }).then((instance) => {
    sieveWasm = instance.instance.exports.sieve;
  })
);

////////////////////////////////////////////////////////////////////////////////

const ITERATIONS = 5;
const LIMIT = 90000000;
const benchmarks = [
  {
    name: "sieve",
    fn: () => {
      outputBuffer = [];
      forth.interpret(`${LIMIT} sieve`);
      return outputBuffer.join("");
    },
  },
  {
    name: "sieve-raw-wasm",
    fn: () => {
      return sieveWasm(LIMIT);
    },
  },
  {
    name: "sieve-js",
    fn: () => {
      const r = sieveJS(LIMIT);
      return r[r.length - 1];
    },
  },
];

////////////////////////////////////////////////////////////////////////////////

const iterations = Array.from(Array(ITERATIONS).keys());

class Benchmarks extends React.Component {
  constructor(props) {
    super(props);
    const results = {};
    benchmarks.forEach(({ name }) => (results[name] = []));
    this.state = {
      initialized: false,
      done: false,
      results,
    };
  }

  componentDidMount() {
    Promise.all(setup).then(() => {
      this.setState({ initialized: true });
      let benchmarkIndex = 0;
      let benchmarkIteration = 0;
      const runNext = () => {
        const t1 = performance.now();
        const output = benchmarks[benchmarkIndex].fn();
        const t2 = performance.now();
        this.setState({
          results: update(this.state.results, {
            [benchmarks[benchmarkIndex].name]: {
              [benchmarkIteration]: {
                $set: { time: (t2 - t1) / 1000.0, output },
              },
            },
          }),
        });
        if (benchmarkIteration < ITERATIONS - 1) {
          benchmarkIteration += 1;
          window.setTimeout(runNext, 500);
        } else if (benchmarkIndex < benchmarks.length - 1) {
          benchmarkIndex += 1;
          benchmarkIteration = 0;
          window.setTimeout(runNext, 500);
        } else {
          this.setState({ done: true });
        }
      };
      window.setTimeout(runNext, 500);
    });
  }

  render() {
    const { initialized, results } = this.state;
    if (!initialized) {
      return <div>Loading</div>;
    }
    return (
      <div>
        <table>
          <thead>
            <tr>
              <th />
              {iterations.map((i) => (
                <th key={i}>{i}</th>
              ))}
              <th>Avg</th>
            </tr>
          </thead>
          <tbody>
            {benchmarks.map(({ name }) => {
              const benchmark = results[name];
              const sum = benchmark.reduce((acc, { time }) => acc + time, 0);
              return [
                <tr key={`${name}-time`}>
                  <th>{name}</th>
                  {iterations.map((i) => (
                    <td key={i}>
                      {benchmark[i] == null ? null : (
                        <span>{benchmark[i].time.toFixed(2)}s</span>
                      )}
                    </td>
                  ))}
                  <th>
                    {benchmark.length === ITERATIONS ? (
                      <span>{(sum / benchmark.length).toFixed(2)}s</span>
                    ) : (
                      "⌛"
                    )}
                  </th>
                </tr>,
                <tr key={`${name}-output`}>
                  <th />
                  {iterations.map((i) => (
                    <td key={i}>
                      <pre className="output">
                        {benchmark[i] == null ? null : benchmark[i].output}
                      </pre>
                    </td>
                  ))}
                </tr>,
              ];
            })}
          </tbody>
        </table>
      </div>
    );
  }
}

const rootEl = document.createElement("div");
document.body.appendChild(rootEl);
createRoot(rootEl).render(<Benchmarks />);
