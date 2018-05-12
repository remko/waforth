let wasmModule;

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
  start() {
    let nextTableBase = 0;
    let table;
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
            emit: this.onEmit,
            key: () => {
              if (buffer.length === 0) {
                //   throw Error("Buffer underrun");
                return -1;
              }
              return buffer.pop();
            },
            load: (offset, length) => {
              // console.log(
              //   "LOAD",
              //   new Uint8Array(this.core.exports.memory.buffer, offset, length),
              //   arrayToBase64(
              //     new Uint8Array(
              //       this.core.exports.memory.buffer,
              //       offset,
              //       length
              //     )
              //   )
              // );
              var tableBase = table.length + nextTableBase;
              if (tableBase >= table.length) {
                table.grow(table.length); // Double size
              }
              var module = new WebAssembly.Module(
                new Uint8Array(this.core.exports.memory.buffer, offset, length)
              );
              new WebAssembly.Instance(module, {
                env: { table, tableBase }
              });
              nextTableBase = nextTableBase + 1;
              return tableBase;
            },
            debug: d => {
              console.log("DEBUG: ", d);
            }
          },
          tmp: {
            number: outOffset => {
              const length = new Uint32Array(
                this.core.exports.memory.buffer,
                0x200,
                4
              )[0];
              const s = new Uint8Array(
                this.core.exports.memory.buffer,
                0x204,
                length
              );
              let sign = 1;
              let val = 0;
              sign = 1;
              if (s[0] === 45) {
                sign = -1;
              } else if (s[0] < 48 || s[0] > 57) {
                return -1;
              } else {
                val = val + s[0] - 48;
              }
              for (let i = 1; i < s.length; ++i) {
                if (s[i] < 48 || s[i] > 57) {
                  return -1;
                }
                val = val * 10 + (s[i] - 48);
              }
              new Int32Array(this.core.exports.memory.buffer, outOffset, 4)[0] =
                sign * val;
              return 0;
            },
            find: (latest, outOffset) => {
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
                0x0000,
                0x4000
              );
              const s4 = new Int32Array(
                this.core.exports.memory.buffer,
                0x0000,
                0x4000
              );
              let p = latest;
              while (p != 0) {
                // console.log("P", p);
                const wordLength = u8[p + 4] & 0x1f;
                const immediate = (u8[p + 4] & 0x80) != 0;
                if (wordLength === length) {
                  let ok = true;
                  for (let i = 0; i < length; ++i) {
                    if (word[i] !== u8[p + 5 + i]) {
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
                p = s4[p / 4];
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
        this._internal = this.core.exports; // For testing
      });
  }

  read(s) {
    const data = new TextEncoder().encode(s);
    for (let i = data.length - 1; i >= 0; --i) {
      this.buffer.push(data[i]);
    }
  }
}

export default WAForth;
