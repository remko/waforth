import WAForth from "../../src/shell/WAForth";
import sieve from "../../src/shell/sieve";
import sieveVanillaModule from "./sieve-vanilla.wasm";
import { Component, render, h } from "preact";
import update from "immutability-helper";
import "./index.css";

////////////////////////////////////////////////////////////////////////////////
// Initial setup
////////////////////////////////////////////////////////////////////////////////

const setup = [];

const forth = new WAForth();
let outputBuffer = [];
forth.onEmit = c => {
  outputBuffer.push(String.fromCharCode(c));
};
setup.push(
  forth.start().then(() => {
    forth.run(sieve);
  })
);

let sieveVanilla;
setup.push(
  WebAssembly.instantiate(sieveVanillaModule, {
    js: {
      print: x => console.log(x)
    }
  }).then(instance => {
    sieveVanilla = instance.instance.exports.sieve;
  })
);

////////////////////////////////////////////////////////////////////////////////

const ITERATIONS = 5;
const LIMIT = 50000000;
const benchmarks = [
  {
    name: "sieve",
    fn: () => {
      outputBuffer = [];
      forth.run(`${LIMIT} sieve`);
      return outputBuffer.join("");
    }
  },
  {
    name: "sieve-vanilla",
    fn: () => {
      return sieveVanilla(LIMIT);
    }
  }
];

////////////////////////////////////////////////////////////////////////////////

const iterations = Array.from(Array(ITERATIONS).keys());

class Benchmarks extends Component {
  constructor(props) {
    super(props);
    const results = {};
    benchmarks.forEach(({ name }) => (results[name] = []));
    this.state = {
      initialized: false,
      done: false,
      results
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
                $set: { time: (t2 - t1) / 1000.0, output }
              }
            }
          })
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
              {iterations.map(i => <th key={i}>{i}</th>)}
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
                  {iterations.map(i => (
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
                  {iterations.map(i => (
                    <td key={i}>
                      <pre className="output">
                        {benchmark[i] == null ? null : benchmark[i].output}
                      </pre>
                    </td>
                  ))}
                </tr>
              ];
            })}
          </tbody>
        </table>
      </div>
    );
  }
}
render(<Benchmarks />, document.body);
