<img src="./doc/logo.svg" height="64">

# [WAForth](https://mko.re/waforth): Forth Interpreter+Compiler for WebAssembly

[![Build](https://github.com/remko/waforth/actions/workflows/build.yml/badge.svg)](https://github.com/remko/waforth/actions/workflows/build.yml)


WAForth is a small bootstrapping Forth interpreter and dynamic compiler for
[WebAssembly](https://webassembly.org). You can see it in action
[in an interactive Forth console](https://mko.re/waforth/), and in [a Logo-like Turtle graphics language](https://mko.re/thurtle/).

It is [entirely written in (raw)
WebAssembly](https://github.com/remko/waforth/blob/master/src/waforth.wat), and
the compiler generates WebAssembly code on the fly. The only parts for which it
relies on external (JavaScript) code is to dynamically load modules (since
WebAssembly [doesn't support JIT
yet](https://webassembly.org/docs/future-features/#platform-independent-just-in-time-jit-compilation)),
and the I/O primitives to read and write a character to a screen.

The WebAssembly module containing the interpreter, dynamic compiler, and 
all built-in words comes down to 13k (6k gzipped), with an extra 7k (3k gzipped) for the JavaScript wrapper and web UI.

WAForth implements all [ANS Core
Words](http://lars.nocrew.org/dpans/dpans6.htm#6.1) (and passes
[Forth 200x Test Suite](https://forth-standard.org/standard/testsuite)
core word tests), and several [ANS Core Extension Words](http://lars.nocrew.org/dpans/dpans6.htm#6.2)

You can read more about the internals and the design of WAForth in the [Design
document](doc/Design.md).


![WAForth Console](doc/console.gif "WAForth Console")


## Using WAForth in a JavaScript application

You can embed WAForth in any JavaScript application. 

A [simple example](https://github.com/remko/waforth/blob/master/src/web/examples/prompt/prompt.ts) to illustrate starting WAForth, and binding JavaScript functions:

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

### Asynchronous bindings

For asynchronous bindings, use `bindAsync` instead of `bind`.

`bindAsync` expects an execution token on the stack, which is
to be called with a success flag after the bound function is called. This is illustrated in [the fetch example](https://github.com/remko/waforth/blob/master/src/web/examples/fetch/fetch.ts):

```typescript
forth.bindAsync("ip?", async () => {
  const result = await (
    await fetch("https://api.ipify.org?format=json")
  ).json();
  forth.pushString(result.ip);
});

forth.interpret(`
( IP? callback. Called after IP address was received )
: IP?-CB ( true c-addr n | false -- )
  IF 
    ." Your IP address is " TYPE CR
  ELSE
    ." Unable to fetch IP address" CR
  THEN
;

( Fetch the IP address, and print it to console )
: IP? ( -- )
  ['] IP?-CB
  S" ip?" SCALL 
;
`);
```

## Goals

Here are some of the goals (and non-goals) of WAForth:

- ✅ **WebAssembly-first**: Implement as much as possible in (raw) WebAssembly. Only call out to JavaScript for functionality that is not available in WebAssembly (I/O, loading compiled WebAssembly code).
- ✅ **Simplicity**: Keep the code as simple as possible. Raw WebAssembly requires more effort to maintain than code in a high level language, so avoid complexity if you can.
- ✅ **Completeness**: Implement a complete (and correct) Forth system, following the [ANS Standard](http://lars.nocrew.org/dpans/dpans.htm), including all [ANS Core words](http://lars.nocrew.org/dpans/dpans6.htm#6.1).
- ❓ **Speed**: If some speed gains can be gotten without paying much in simplicity (e.g. better design of the system, more efficient implementation of words, simple compiler improvements, ...), then I do it. However, generating the most efficient code would require a smart compiler, and a smart compiler would introduce a lot of complexity if implemented in raw WebAssembly, so speed is not an ultimate goal. Although the low level of WebAssembly gives some speed advantages, the design of the system will cause execution to consist almost exclusively of indirect calls to small functions, so there will be languages targeting WebAssembly that run faster.
- ❌ **Binary size**: Since the entire system is written in raw WebAssembly, and since one of the main goals is simplicity, the resulting binary size is naturally quite small (±12k). However, I don't do any special efforts to save bytes here and there in the code (or the generated code) if it makes things more complex.
- ❌ **Ease of use**: I currently don't make any effort to provide functionality to make Forth programming easy (helpful errors, ...). However, the compiler emits debug information to help step through the WebAssembly code of words, and I hope to add more debugging aids to the compiler in the future.

![Debugger view of a compiled
word](doc/debugger.png "Debugger view of a
compiled word")

## Development

### Install Dependencies

The build uses the [WebAssembly Binary
Toolkit](https://github.com/WebAssembly/wabt) for converting raw WebAssembly
text format into the binary format, and [Yarn](https://yarnpkg.com) (and therefore
[Node.JS](https://nodejs.org/en/)) for
managing the build process and the dependencies of the shell.

    brew install wabt yarn
    yarn


### Building & Running

To build everything:
    
    yarn build

To run the development server:

    yarn dev

### Testing

The tests are served from `/waforth/tests` by the development server.

You can also run the tests in Node.JS by running

    yarn test
