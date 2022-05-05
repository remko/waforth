<img src="./doc/logo.svg" height="64">

# [WAForth](https://mko.re/waforth): Forth Interpreter+Compiler for WebAssembly

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

WAForth is still in an experimental stage. It implements most of the [ANS Core
Words](http://lars.nocrew.org/dpans/dpans6.htm#6.1), and passes most of the
[Forth 200x Test Suite](https://forth-standard.org/standard/testsuite)
core word tests.

![WAForth Console](https://mko.re/waforth/console.gif "WAForth Console")


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

  // Bind "prompt" call to a function that pops up a JavaScript prompt, and pushes the entered number back on the stack
  forth.bind("prompt", (stack) => {
    const message = stack.popString();
    const result = window.prompt(message);
    stack.push(parseInt(result));
  });

  // Load Forth code to bind the "prompt" call to a word, and call the word
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

## Development

### Install Dependencies

The build uses the [WebAssembly Binary
Toolkit](https://github.com/WebAssembly/wabt) for converting raw WebAssembly
text format into the binary format, and [Yarn](https://yarnpkg.com) for
managing the dependencies of the shell.

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

## Design

The WAForth core is written as [a single
module](https://github.com/remko/waforth/blob/master/src/waforth.wat) in
WebAssembly's [text
format](https://webassembly.github.io/spec/core/text/index.html).

### The Interpreter

The interpreter runs a loop that processes commands, and switches to and from
compiler mode. 

Contrary to some other Forth systems, this system doesn't use direct threading
for executing code. WebAssembly doesn't allow unstructured jumps, let alone
dynamic jumps.  Instead, WAForth uses subroutine threading, where each word
is implemented as a single WebAssembly function, and the system uses calls
and indirect calls (see below) to execute words.


### The Compiler

While in compile mode for a word, the compiler generates WebAssembly
instructions in binary format (since there is no assembler infrastructure in
the browser). Since WebAssembly [doesn't support JIT compilation
yet](https://webassembly.org/docs/future-features/#platform-independent-just-in-time-jit-compilation),
a finished word is bundled into a separate binary WebAssembly module, and sent
to the loader, which dynamically loads it and registers it with  a shared
[function
table](https://webassembly.github.io/spec/core/valid/modules.html#tables) at
the next offset, which in turn is recorded in the word dictionary. 

Because words reside in different modules, all calls to and from the words need
to happen as indirect `call_indirect` calls through the shared function table.
This of course introduces some overhead, although it appears limited.

As WebAssembly doesn't support unstructured jumps, control flow words
(`IF/ELSE/THEN`, `LOOP`, `REPEAT`, ...) can't be implemented in terms of more
basic words, unlike in jonesforth.  However, since Forth only requires
structured jumps, the compiler can easily be implemented using the loop and
branch instructions available in WebAssembly.

Finally, the compiler adds minimal debug information about the compiled word in
the [name
section](https://github.com/WebAssembly/design/blob/master/BinaryEncoding.md#name-section),
making it easier for doing some debugging in the browser.

![Debugger view of a compiled
word](doc/debugger.png "Debugger view of a
compiled word")


### The Loader

The loader is a small bit of JavaScript that uses the [WebAssembly JavaScript
API](https://webassembly.github.io/spec/js-api/index.html) to dynamically load
a compiled word (in the form of a WebAssembly module), and ensuring that the
shared function table is large enough for the module to register itself.

### The Shell

The shell is [a JavaScript
class](https://github.com/remko/waforth/blob/master/src/shell/WAForth.js) that
wraps the WebAssembly module, and loads it in the browser.  It provides the I/O
primitives to the WebAssembly module to read and write characters to a
terminal, and externally provides a `interpret()` function to execute a fragment of
Forth code.

To tie everything together into an interactive system, there's a small
console-based interface around this shell to type Forth code, which you can see
in action [here](https://mko.re/waforth/).

