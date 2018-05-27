let wasmModule;

const isSafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent);

// eslint-disable-next-line no-unused-vars
function arrayToBase64(bytes) {
  var binary = "";
  var len = bytes.byteLength;
  for (var i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return window.btoa(binary);
}

class WAForth {
  start(options = {}) {
    const { skipPrelude } = options;
    let nextTableBase = 0;
    let table;
    let tableStart;
    const buffer = (this.buffer = []);

    // TODO: Try to bundle this. See https://github.com/parcel-bundler/parcel/issues/647
    const initialize =
      wasmModule != null
        ? Promise.resolve(wasmModule)
        : fetch("waforth.wasm")
            .then(resp => resp.arrayBuffer())
            .then(module => {
              wasmModule = module;
              return wasmModule;
            });
    return initialize
      .then(m =>
        WebAssembly.instantiate(m, {
          shell: {
            ////////////////////////////////////////
            // I/O
            ////////////////////////////////////////

            emit: this.onEmit,

            key: () => {
              if (buffer.length === 0) {
                return -1;
              }
              return buffer.pop();
            },

            debug: d => {
              console.log("DEBUG: ", d);
            },

            ////////////////////////////////////////
            // Loader
            ////////////////////////////////////////

            load: (offset, length) => {
              let data = new Uint8Array(
                this.core.exports.memory.buffer,
                offset,
                length
              );
              if (isSafari) {
                // On Safari, using the original Uint8Array triggers a bug.
                // Taking an element-by-element copy of the data first.
                let dataCopy = [];
                for (let i = 0; i < length; ++i) {
                  dataCopy.push(data[i]);
                }
                data = new Uint8Array(dataCopy);
              }
              var tableBase = tableStart + nextTableBase;
              if (tableBase >= table.length) {
                table.grow(table.length); // Double size
              }
              // console.log(
              //   "Load",
              //   tableBase,
              //   new Uint8Array(data),
              //   arrayToBase64(data)
              // );
              var module = new WebAssembly.Module(data);
              new WebAssembly.Instance(module, {
                env: { table, tableBase }
              });
              nextTableBase = nextTableBase + 1;
              return tableBase;
            }
          }
        })
      )
      .then(instance => {
        this.core = instance.instance;
        table = this.core.exports.table;
        tableStart = table.length;
        if (!skipPrelude) {
          this.core.exports.loadPrelude();
        }
      });
  }

  read(s) {
    const data = new TextEncoder().encode(s);
    for (let i = data.length - 1; i >= 0; --i) {
      this.buffer.push(data[i]);
    }
  }

  run(s) {
    this.read(s);
    return this.core.exports.interpret();
  }
}

export default WAForth;
