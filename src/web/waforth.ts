import wasmModule from "../waforth.wat";

const isSafari =
  typeof navigator != "undefined" &&
  /^((?!chrome|android).)*safari/i.test(navigator.userAgent);

const PAD_OFFSET = 400;

// eslint-disable-next-line no-unused-vars, @typescript-eslint/no-unused-vars
const arrayToBase64 =
  typeof Buffer === "undefined"
    ? function arrayToBase64(bytes: Uint8Array) {
        let binary = "";
        const len = bytes.byteLength;
        for (let i = 0; i < len; i++) {
          binary += String.fromCharCode(bytes[i]);
        }
        return window.btoa(binary);
      }
    : function arrayToBase64(s: Uint8Array) {
        return Buffer.from(s).toString("base64");
      };

function loadString(memory: WebAssembly.Memory, addr: number, len: number) {
  return String.fromCharCode.apply(
    null,
    new Uint8Array(memory.buffer, addr, len) as any
  );
}

function saveString(s: string, memory: WebAssembly.Memory, addr: number) {
  const len = s.length;
  const a = new Uint8Array(memory.buffer, addr, len);
  for (let i = 0; i < len; ++i) {
    a[i] = s.charCodeAt(i);
  }
}

enum ErrorCode {
  Unknown = 0x1, // Unknown error
  Quit = 0x2, // QUIT was called
  Abort = 0x3, // ABORT or ABORT" was called
  EOI = 0x4, // No more input
}

/**
 * JavaScript shell around the WAForth WebAssembly module.
 *
 * Provides higher-level functions to interact with the WAForth WebAssembly module.
 *
 * To the WebAssembly module, provides the infrastructure to dynamically load WebAssembly modules and
 * the I/O primitives with the UI.
 * */
class WAForth {
  core?: WebAssembly.Instance;
  #buffer?: string;
  #fns: Record<string, (f: WAForth) => void>;

  /**
   * Callback that is called when a character needs to be emitted.
   *
   * `c` is the ASCII code of the character to be emitted.
   */
  onEmit?: (c: string) => void;
  key: () => number;

  constructor() {
    this.#fns = {};
    this.onEmit = (() => {
      // Default emit that logs to console
      let buffer: string[] = [];
      return (c: string) => {
        if (c === "\n") {
          console.log(buffer.join(""));
          buffer = [];
        } else {
          buffer.push(c);
        }
      };
    })();

    const keyBuffer: string[] = [];
    this.key = () => {
      while (keyBuffer.length === 0) {
        const c = window.prompt("Enter text");
        if (c == null) {
          continue;
        }
        keyBuffer.push(...c.split(""));
        if (c.length === 0 || c.length > 1) {
          keyBuffer.push("\n");
        }
      }
      return keyBuffer.shift()!.charCodeAt(0);
    };
  }

  /**
   * Initialize WAForth.
   *
   * Needs to be called before interpret().
   */
  async load() {
    this.#buffer = "";

    const instance = await WebAssembly.instantiate(wasmModule, {
      shell: {
        ////////////////////////////////////////
        // I/O
        ////////////////////////////////////////

        emit: (c: number) => {
          if (this.onEmit) {
            this.onEmit(String.fromCharCode(c));
          }
        },

        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        read: (addr: number, length: number): number => {
          let input: string;
          const i = this.#buffer!.indexOf("\n");
          if (i === -1) {
            input = this.#buffer!;
            this.#buffer = "";
          } else {
            input = this.#buffer!.substring(0, i + 1);
            this.#buffer = this.#buffer!.substring(i + 1);
          }
          // console.log("read: %s (%d remaining)", input, this.#buffer!.length);
          saveString(
            input,
            this.core!.exports.memory as WebAssembly.Memory,
            addr
          );
          return input.length;
        },

        key: () => {
          return this.key();
        },

        ////////////////////////////////////////
        // Loader
        ////////////////////////////////////////

        load: (offset: number, length: number) => {
          let data = new Uint8Array(
            (this.core!.exports.memory as WebAssembly.Memory).buffer,
            offset,
            length
          );
          if (isSafari) {
            // On Safari, using the original Uint8Array triggers a bug.
            // Taking an element-by-element copy of the data first.
            const dataCopy = [];
            for (let i = 0; i < length; ++i) {
              dataCopy.push(data[i]);
            }
            data = new Uint8Array(dataCopy);
          }
          // console.log("Load", arrayToBase64(data));
          try {
            const module = new WebAssembly.Module(data);
            new WebAssembly.Instance(module, {
              env: { table, memory },
            });
          } catch (e) {
            console.error(e);
            throw e;
          }
        },

        ////////////////////////////////////////
        // Generic call
        ////////////////////////////////////////

        call: () => {
          const len = this.pop();
          const addr = this.pop();
          const fname = loadString(memory, addr, len);
          const fn = this.#fns[fname];
          if (!fn) {
            console.error("Unbound SCALL: %s", fname);
          } else {
            fn(this);
          }
        },
      },
    });
    this.core = instance.instance;
    const table = this.core.exports.table as WebAssembly.Table;
    const memory = this.core.exports.memory as WebAssembly.Memory;
  }

  memory(): WebAssembly.Memory {
    return this.core!.exports.memory as WebAssembly.Memory;
  }

  here(): number {
    return (this.core!.exports.here as any)() as number;
  }

  pop(): number {
    return (this.core!.exports.pop as any)();
  }

  popString(): string {
    const len = this.pop();
    const addr = this.pop();
    return loadString(this.memory(), addr, len);
  }

  push(n: number): void {
    (this.core!.exports.push as any)(n);
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  pushString(s: string, offset = 0): number {
    const addr = this.here() + PAD_OFFSET;
    saveString(s, this.memory(), addr);
    this.push(addr);
    this.push(s.length);
    return addr + PAD_OFFSET;
  }

  /**
   * Read data `s` into the input buffer without interpreting it.
   */
  read(s: string) {
    this.#buffer = this.#buffer + s;
  }

  /**
   * Read data `s` into the input buffer, and start interpreter.
   */
  interpret(s: string, silent = false) {
    if (!s.endsWith("\n")) {
      s = s + "\n";
    }
    this.read(s);
    try {
      return (this.core!.exports.run as any)(silent);
    } catch (e) {
      // Exceptions thrown from the core means QUIT or ABORT is called, or an error
      // has occurred.
      if ((this.core!.exports.error as any)() === ErrorCode.Unknown) {
        console.error(e);
      }
    }
    return (this.core!.exports.error as any)() as ErrorCode;
  }

  /**
   * Bind `name` to SCALL in Forth.
   *
   * When an SCALL is done with `name` on the top of the stack, `fn` will be called (with the name popped off the stack).
   * Use `stack` to pop parameters off the stack, and push results back on the stack.
   */
  bind(name: string, fn: (f: WAForth) => void) {
    this.#fns[name] = fn;
  }

  /**
   * Bind async `name` to SCALL in Forth.
   *
   * When an SCALL is done with `name` on the top of the stack, `fn` will be called (with the name popped off the stack).
   * Expects an execution token on the top of the stack, which will be called when the async callback is finished.
   * The execution parameter will be called with the success flag set.
   */
  bindAsync(name: string, fn: (f: WAForth) => Promise<void>) {
    this.#fns[name] = async () => {
      const cbxt = this.pop();
      try {
        await fn(this);
        this.push(-1);
      } catch (e) {
        console.error(e);
        this.push(0);
      } finally {
        this.push(cbxt);
        this.interpret("EXECUTE");
      }
    };
  }
}

export default WAForth;
