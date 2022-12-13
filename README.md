<img src="./doc/logo.svg" height="64">

# [WAForth](https://mko.re/waforth): Forth Interpreter+Compiler for WebAssembly

[![Build](https://github.com/remko/waforth/actions/workflows/build.yml/badge.svg)](https://github.com/remko/waforth/actions/workflows/build.yml)


WAForth is a small but complete bootstrapping Forth interpreter and dynamic compiler for
[WebAssembly](https://webassembly.org). You can see it in action
[in an interactive Forth console](https://mko.re/waforth/), and in [a Logo-like Turtle graphics language](https://mko.re/thurtle/).

WAForth is [entirely written in (raw)
WebAssembly](https://github.com/remko/waforth/blob/master/src/waforth.wat), and
the compiler generates WebAssembly code on the fly. The only parts for which it
relies on external code is to dynamically load modules (since
WebAssembly [doesn't support JIT
yet](https://webassembly.org/docs/future-features/#platform-independent-just-in-time-jit-compilation)),
and the I/O primitives to read and write a character to a screen.

The WebAssembly module containing the interpreter, dynamic compiler, and 
all built-in words comes down to 14k (7k gzipped), with an extra 15k (7k gzipped) for the JavaScript wrapper, web UI, 
and encoding overhead.

WAForth implements all [ANS Core
Words](http://lars.nocrew.org/dpans/dpans6.htm#6.1) (and passes [Forth 200x
Test Suite](https://forth-standard.org/standard/testsuite) core word tests),
and many [ANS Core Extension
Words](http://lars.nocrew.org/dpans/dpans6.htm#6.2). You can get the complete
list of supported words [from the interactive
console](https://mko.re/waforth/?p=WORDS).

You can read more about the internals and the design of WAForth in the [Design
document](doc/Design.md).

<div align="center">
<div>
<a href="https://mko.re/waforth/"><img src="https://raw.githubusercontent.com/remko/waforth/master/doc/console.gif" alt="WAForth console"></a>
</div>
<figcaption><em><a href="https://mko.re/waforth/">WAForth console</a></em></figcaption>
</div>

<div align="center">
<div>
<a href="https://mko.re/thurtle/"><img style="width: 550px; margin-top: 1.5em;" src="https://raw.githubusercontent.com/remko/waforth/master/doc/thurtle.png" alt="Thurtle program"></a>
</div>
<figcaption><em>WAForth integrated in <a href="https://mko.re/thurtle/">Thurtle</a>, a <a href="https://en.wikipedia.org/wiki/Turtle_graphics">turtle graphics</a> programming environment using Forth</em></figcaption>
</div>

## Standalone shell

Although WebAssembly (and therefore WAForth) is typically used in a web environment 
(web browsers, Node.js), WAForth also has a standalone native command-line shell. 
You can download a pre-built binary of the standalone shell from 
[the Releases page](https://github.com/remko/waforth/releases).

The standalone shell uses the [Wasmtime](https://wasmtime.dev) engine,
but its build configuration can easily be adapted to build using any 
WebAssembly engine that supports the
[WebAssembly C API](https://github.com/WebAssembly/wasm-c-api) (although some
engines have [known issues](https://github.com/remko/waforth/issues/6#issue-326830993)).

<div align="center">
<div>
<a href="https://mko.re/thurtle/"><img style="width: 550px;" src="https://raw.githubusercontent.com/remko/waforth/master/doc/standalone.png" alt="Thurtle program"></a>
</div>
<figcaption><em>Standalone WAForth shell executable</em></figcaption>
</div>

## Native compiler

Besides just-in-time compilation (in a browser or native), WAForth can also be used to compile Forth ahead-of-time.
[`waforthc`](https://github.com/remko/waforth/tree/master/src/waforthc) is a tool that uses WAForth to compile a Forth program into a native executable.
WebAssembly is used as the host runtime platform and intermediate representation during compilation, and then compiled into an executable
that no longer contains any WebAssembly infrastructure.

## Using WAForth in a JavaScript application

You can embed WAForth in any JavaScript application. 

A [simple example](https://github.com/remko/waforth/blob/master/src/web/examples/prompt/prompt.ts) ([CodePen](https://codepen.io/mko-re/pen/gOzzmXZ)) to illustrate starting WAForth, and binding JavaScript functions:

```typescript
import WAForth, { withLineBuffer } from "waforth";

(async () => {
  // Create the UI
  document.body.innerHTML = `<button>Go!</button><pre></pre>`;
  const btn = document.querySelector("button");
  const log = document.querySelector("pre");

  // Initialize WAForth
  const forth = new WAForth();
  forth.onEmit = withLineBuffer((c) =>
    log.appendChild(document.createTextNode(c)));
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


## Writing WebAssembly in Forth

WAForth supports directly writing WebAssembly in Forth using the [`CODE`](https://forth-standard.org/standard/tools/CODE) word.
For example, the following snippet defines a raw WebAssembly version of [`DUP`](https://forth-standard.org/standard/core/DUP):

```forth
CODE DUP' ( n -- n n )
  \ Put pointer to top of Forth stack (local_0) on the 
  \ Wasm operand stack (for use later)
  [ 0 ] $LOCAL.GET

  \ Load the number at the top of the Forth stack 
  \ (local_0 - 4) on the Wasm operand stack
  [ 0 ] $LOCAL.GET
  [ 4 ] $I32.CONST
  $I32.SUB
  $I32.LOAD

  \ Store the number on the Wasm operand stack on 
  \ top of the Forth stack. The first operand (Forth 
  \ stack pointer) was put on the Wasm operand stack 
  \ at the beginning of this snippet
  $I32.STORE

  \ Increment the Forth top of stack pointer (local_0), 
  \ and leave it on the Wasm operand stack as return value
  [ 0 ] $LOCAL.GET
  [ 4 ] $I32.CONST 
  $I32.ADD
;CODE
```

This creates a word with the specified WebAssembly:

```wasm
(func $DUP' (param $tos i32) (result i32)
  local.get $tos
  local.get $tos
  i32.const 4
  i32.sub
  i32.load
  i32.store
  local.get $tos
  i32.const 4
  i32.add
)
```

Note that support for writing WebAssembly is still experimental.
The assembly words used in the above snippet (`$LOCAL.GET`, `$I32.*`, ...) aren't available in the WAForth core,
and have to be manually defined using the low-level `$U,` and `$S,` words that append ([LEB128](https://en.wikipedia.org/wiki/LEB128)-encoded) bytes directly to the WebAssembly module. For example, the code above relies on the following assembly word definitions:

```forth
: $LOCAL.GET ( u -- )   32 $U, $U,         ; IMMEDIATE
: $I32.ADD   ( -- )    106 $U,             ; IMMEDIATE
: $I32.SUB   ( -- )    107 $U,             ; IMMEDIATE
: $I32.CONST ( n -- )   65 $U, $S,         ; IMMEDIATE
: $I32.LOAD  ( -- )     40 $U, 2 $U, 0 $U, ; IMMEDIATE
: $I32.STORE ( -- )     54 $U, 2 $U, 0 $U, ; IMMEDIATE
```

The exact opcodes and format of instructions can be found in
[the WebAssembly spec](https://webassembly.github.io/spec/core/binary/instructions.html). In the future, I'll probably make all WebAssembly assembly instructions available somewhere. Using WebAssembly locals also currently isn't possible, although this should be easy to add later.  


## Notebooks

The [WAForth Visual Studio Code Extension](https://marketplace.visualstudio.com/items?itemName=remko.waforth-vscode-extension) adds support
for interactive Forth notebooks powered by WAForth. Thes lets you create documents that combine rich text with executable Forth code.
You can execute both text-based Forth code, as well as [Thurtle](https://mko.re/thurtle/) graphics.

Because it is powered by WebAssembly, this extension works both in the desktop version of Visual Studio Code and in [the browser version of Visual Studio Code](https://code.visualstudio.com/docs/editor/vscode-web) (e.g. https://github.dev, https://vscode.dev).

You can also convert the notebook into a lightweight self-contained page using [`wafnb2html`](https://github.com/remko/waforth/tree/master/src/web/notebook).
An example can be seen [here](https://mko.re/wafnb/drawing-with-forth).

<div align="center">
<div>
<a href="https://github.dev/remko/waforth/blob/master/src/web/notebook/examples/drawing-with-forth.wafnb"><img src="https://raw.githubusercontent.com/remko/waforth/master/src/web/vscode-extension/doc/notebook.gif" alt="WAForth notebook"></a>
</div>
<figcaption><em><a href="https://github.dev/remko/waforth/blob/master/src/web/notebook/examples/drawing-with-forth.wafnb">WAForth notebook</a></em></figcaption>
</div>


## Goals

Here are some of the goals (and non-goals) of WAForth:

- ✅ **WebAssembly-first**: Implement as much as possible in (raw) WebAssembly. Only call out to JavaScript for functionality that is not available in WebAssembly (I/O, loading compiled WebAssembly code).
- ✅ **Simplicity**: Keep the code as simple and clean as possible. Raw WebAssembly requires more effort to maintain than code in a high level language, so avoid complexity if you can.
- ✅ **Completeness**: Implement a complete (and correct) Forth system, following the [ANS Standard](http://lars.nocrew.org/dpans/dpans.htm), including all [ANS Core words](http://lars.nocrew.org/dpans/dpans6.htm#6.1).
- ❓ **Speed**: If some speed gains can be gotten without paying much in simplicity (e.g. better design of the system, more efficient implementation of words, simple compiler improvements, ...), then I do it. However, generating the most efficient code would require a smart compiler, and a smart compiler would introduce a lot of complexity if implemented in raw WebAssembly, so speed is not an ultimate goal. Although the low level of WebAssembly gives some speed advantages, the design of the system will cause execution to consist almost exclusively of indirect calls to small functions, so there will be languages targeting WebAssembly that run faster.
- ❓ **Binary size**: Since the entire system is written in raw WebAssembly, and since one of the main goals is simplicity, the resulting binary size is naturally quite small (±12k). However, I don't do any special efforts to save bytes here and there in the code (or the generated code) if it makes things more complex.
- ❓ **Ease of use**: Like most Forths, I currently don't do much effort to provide functionality to make Forth programming easy and safe (helpful errors, stacktraces, strict bounds checks, ...). However, the compiler emits debug information to help step through the WebAssembly code of words, and I hope to add more debugging aids to the compiler in the future (if it doesn't add too much complexity)

![Debugger view of a compiled word](doc/debugger.png "Debugger view of a compiled word")

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
