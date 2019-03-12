# [WAForth](https://el-tramo.be/waforth): Forth Interpreter+Compiler for WebAssembly

WAForth is a bootstrapping Forth interpreter and dynamic compiler for
[WebAssembly](https://webassembly.org). You can see it in a demo
[here](https://el-tramo.be/waforth/).

It is (almost) entirely written in WebAssembly and Forth, and the compiler
generates WebAssembly code on the fly. The only parts for which it relies on
external (JavaScript) code is the dynamic loader (since WebAssembly [doesn't
support JIT
yet](https://webassembly.org/docs/future-features/#platform-independent-just-in-time-jit-compilation)),
and the I/O primitives to read and write a character.

Parts of the implementation were influenced by
[jonesforth](http://git.annexia.org/?p=jonesforth.git;a=summary), and I
shamelessly stole the Forth code of some of its high-level words.

WAForth is still in an experimental stage.

## Install Dependencies

The build uses [Racket](https://racket-lang.org) for processing the WebAssembly
code, the [WebAssembly Binary Toolkit](https://github.com/WebAssembly/wabt) for
converting it in binary format,and [Yarn](https://yarnpkg.com) for managing the
dependencies of the shell.

    brew install wabt yarn minimal-racket
    yarn


## Building & Running

To build everything:
    
    make

To run the development server:

    make dev-server

## Testing

The tests are served from `/tests` by the development server.

You can also run the tests in Node.JS by running

    make check

## Design

### The Macro Assembler

The WAForth core is written as [a single
module](https://github.com/remko/waforth/blob/master/src/waforth.wat) in
WebAssembly's [text
format](https://webassembly.github.io/spec/core/text/index.html). The text
format isn't really meant for writing code in, so it has no facilities like a
real assembler (e.g. constant definitions, macro expansion, ...) However, since
the text format uses S-expressions, you can do some small modifications to make
it extensible with Lisp-style macros. 

I added some Racket macros to the module definition, and implemented [a mini
assembler](https://github.com/remko/waforth/blob/master/src/tools/assembler.rkt)
to print out the resulting s-expressions in the right format.

The result is something that looks like a standard WebAssembly module, but
sprinkled with some macros for convenience.

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
This of course introduces some overhead, although it seems limited.

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
word](https://el-tramo.be/blog/waforth/debugger.png "Debugger view of a
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
terminal, and externally provides a `run()` function to execute a fragment of
Forth code.

To tie everything together into an interactive system, there's a small
console-based interface around this shell to type Forth code, which you can see
in action [here](https://el-tramo.be/waforth/).

![WAForth Console](https://el-tramo.be/waforth/console.gif "WAForth Console")

### Misc notes

- The exposed return stack isn't used. Control flow is kept implicitly in the
  code (e.g. through branches, indirect calls, ...). This also means that
  control flow can't be influenced by code.
