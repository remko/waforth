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
              var module = new WebAssembly.Module(data);
              // console.log("Load", tableBase, new Uint8Array(data), arrayToBase64(data));
              new WebAssembly.Instance(module, {
                env: { table, tableBase }
              });
              nextTableBase = nextTableBase + 1;
              return tableBase;
            }
          },
          tmp: {
            find: (latest, outOffset) => {
              const DICT_BASE = 0x20000;
              const wordAddr = new Int32Array(
                this.core.exports.memory.buffer,
                outOffset - 4,
                4
              )[0];
              const length = new Uint32Array(
                this.core.exports.memory.buffer,
                wordAddr,
                4
              )[0];
              const word = new Uint8Array(
                this.core.exports.memory.buffer,
                wordAddr + 4,
                length
              );
              const out = new Int32Array(
                this.core.exports.memory.buffer,
                outOffset - 4,
                8
              );
              // console.log("FIND", wordAddr, length, word);
              const u8 = new Uint8Array(
                this.core.exports.memory.buffer,
                DICT_BASE,
                0x10000
              );
              const s4 = new Int32Array(
                this.core.exports.memory.buffer,
                DICT_BASE,
                0x10000
              );
              let p = latest;
              while (p != 0) {
                // console.log("P", p);
                const wordLength = u8[p - DICT_BASE + 4] & 0x1f;
                const hidden = u8[p - DICT_BASE + 4] & 0x20;
                const immediate = (u8[p - DICT_BASE + 4] & 0x80) != 0;
                if (hidden == 0 && wordLength === length) {
                  let ok = true;
                  for (let i = 0; i < length; ++i) {
                    if (word[i] !== u8[p - DICT_BASE + 5 + i]) {
                      ok = false;
                      break;
                    }
                  }
                  if (ok) {
                    // console.log("Found!");
                    out[0] = p;
                    out[1] = immediate ? 1 : -1;
                    return;
                  }
                }
                p = s4[(p - DICT_BASE) / 4];
              }
              out[1] = 0;
              // console.log("Not found");
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
