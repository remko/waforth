<img src="./doc/logo.svg" height="64">

# [WAForth](https://mko.re/waforth): Forth Interpreter+Compiler for WebAssembly

[![Build](https://github.com/remko/waforth/actions/workflows/build.yml/badge.svg)](https://github.com/remko/waforth/actions/workflows/build.yml)


WAForth is a small bootstrapping Forth interpreter and dynamic compiler for
[WebAssembly](https://webassembly.org). You can see it in a demo
[here](https://mko.re/waforth/).

It is [entirely written in (raw)
WebAssembly](https://github.com/remko/waforth/blob/master/src/waforth.wat), and
the compiler generates WebAssembly code on the fly. The only parts for which it
relies on external (JavaScript) code is to dynamically load modules (since
WebAssembly [doesn't support JIT
yet](https://webassembly.org/docs/future-features/#platform-independent-just-in-time-jit-compilation)),
and the I/O primitives to read and write a character to a screen.

The WebAssembly module containing the interpreter, dynamic compiler, and 
all built-in words comes down to 13k (6k gzipped), with an extra 7k (3k gzipped) for the JavaScript wrapper and web UI.

WAForth implements all of the [ANS Core
Words](http://lars.nocrew.org/dpans/dpans6.htm#6.1) (and passes
[Forth 200x Test Suite](https://forth-standard.org/standard/testsuite)
core word tests), and several [ANS Core Extension Words](http://lars.nocrew.org/dpans/dpans6.htm#6.2)

![WAForth Console](doc/console.gif "WAForth Console")


## Using WAForth in an application

You can embed WAForth in any JavaScript application. 

A simple example to illustrate starting WAForth, and binding JavaScript functions:

```typescript
import WAForth from "waforth";

(async () => {
  // Create the UI
  document.body.innerHTML = `<button>Go!</button><pre></pre>`;
  const btn = document.querySelector("button");
  const log = document.querySelector("pre");

  // Initialize WAForth
  const forth = new WAForth();
  forth.onEmit = (c) =>
    log.appendChild(document.createTextNode(String.fromCharCode(c)));
  await forth.load();

  // Bind "prompt" call to a function that pops up a JavaScript 
  // prompt, and pushes the entered number back on the stack
  forth.bind("prompt", (stack) => {
    const message = stack.popString();
    const result = window.prompt(message);
    stack.push(parseInt(result));
  });

  // Load Forth code to bind the "prompt" call to a word, 
  // and call the word
  forth.interpret(`
( Call "prompt" with the given string )
: PROMPT ( c-addr u -- n )
  S" prompt" SCALL 
;

( Prompt the user for a number, and write it to output )
: ASK-NUMBER ( -- )
  S" Please enter a number" PROMPT
  ." The number was" SPACE .
;
`);

  btn.addEventListener("click", () => {
    forth.interpret("ASK-NUMBER");
  });
})();
```

## Goals

Here are some of the goals (and non-goals) of WAForth:

- ✅ **WebAssembly-first**: Implement as much as possible in (raw) WebAssembly. Only call out to JavaScript for functionality that is not available in WebAssembly (I/O, loading compiled WebAssembly code).
- ✅ **Simplicity**: Keep the code as simple as possible. Raw WebAssembly code requires more effort to maintain than code in a high level language, so avoid complexity if you can.
- ✅ **Completeness**: Implement a complete (and correct) ANS Forth system, including all the ANS Core words.
- ❓ **Speed**: If some speed gains can be gotten without paying much in simplicity (e.g. better design of the system, more efficient implementation of words, simple compiler improvements, ...), then I do it. However, generating the most efficient code would require a smart compiler, and a smart compiler would introduce a lot of complexity if implemented in raw WebAssembly, so speed is not an ultimate goal. Although the low level of WebAssembly gives some speed advantages, the design of the system will cause execution to consist almost exclusively of indirect calls to small functions, so high speed isn't to be expected.
- ❌ **Binary size**: Since the entire system is written in raw WebAssembly, and since one of the main goals is simplicity, the resulting binary size is naturally quite small (±12k). However, I don't do any special efforts to save bytes here and there in the code (or the generated code) if it makes things more complex.
- ❌ **Ease of use**: I currently don't make any effort to provide functionality to make Forth programming easy (helpful errors, ...). However, the compiler emits debug information to help step through the WebAssembly code of words.

![Debugger view of a compiled
word](doc/debugger.png "Debugger view of a
compiled word")

## Development

You can read more about the internals and the design of WAForth in the [Design document](doc/Design.md).

Below you can find instructions on setting up a development environment.

### Install Dependencies

The build uses the [WebAssembly Binary
Toolkit](https://github.com/WebAssembly/wabt) for converting raw WebAssembly
text format into the binary format, and [Yarn](https://yarnpkg.com) for
managing the build process and the dependencies of the shell.

    brew install wabt yarn
    yarn


### Building & Running

To build everything:
    
    make

To run the development server:

    make dev

### Testing

The tests are served from `/waforth/tests` by the development server.

You can also run the tests in Node.JS by running

    make check
