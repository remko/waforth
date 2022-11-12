# `waforthc`: (WebAssembly-based) Forth native compiler

`waforthc` uses [WAForth](https://github.com/remko/waforth), 
[WABT](https://github.com/WebAssembly/wabt), and the host's C compiler to compile a Forth program into a native executable. WebAssembly is used as the host 
runtime platform and intermediate representation during compilation, and then compiled into an executable
that no longer contains any WebAssembly infrastructure. See [*How it works*](#how-it-works) for more details.

## Download

*Binary releases are coming when WABT 1.0.31 is released*

## Usage example

Let's compile a program `hello.fs`:

    $ cat hello.fs↩
    .( Compiling word... ) 
    : SAY_HELLO  
      ." Hello, Forth" CR 
    ; 
    .( Compiled! Running compiled word from within compiler: )
    SAY_HELLO

    $ waforthc --output=hello hello.fs↩
    Compiling word... Compiled! Running compiled word from within compiler: Hello, Forth

Since the Forth compiler is dynamic, you can execute previously compiled functions from within the compiler, as you can see from the console
output above.

By default, the resulting executable is a standalone interactive Forth
interpreter, with the compiled functions available:

    $ ./hello↩
    4 2 * .↩
    8 ok
    SAY_HELLO↩
    Hello, Forth
    ok
    BYE↩

Instead of an interactive shell that accepts user input, you can also tell `waforthc` to make the executable run a fixed script when it is started:

    $ waforthc --output=hello --init=SAY_HELLO hello.fs↩
    Compiling word... Compiled! Running compiled word from within compiler: Hello, Forth

    $ ./hello↩
    Hello, Forth

Contrary to the [standalone native WAForth](https://github.com/remko/waforth/tree/master/src/standalone), the resulting binary does not contain a WebAssembly engine, and therefore the compiler infrastructure is no longer available:

    $ ls -l hello↩
    -rwxr-xr-x 1 remko remko 159k Nov 11 13:18 hello

    $ ./hello↩
    : SAY_BYE ." Bye" CR ;
    Compilation is not available in native compiled mode

If you have a cross-compiling C compiler, you can also cross-compile your Forth program to a different architecture:

    $ waforthc --cc=arm-linux-gnueabi-gcc --ccflag=-static --output=hello --init=SAY_HELLO hello.fs↩

## How it works

The `waforthc` compiler ([`waforthc.cpp`](https://github.com/remko/waforth/blob/master/src/waforthc/waforthc.cpp)) works as follows:

- `waforthc` runs an embedded [WAForth WebAssembly module](https://github.com/remko/waforth/blob/master/src/waforth.wat) using the 
  [WABT](https://github.com/WebAssembly/wabt) reference WebAssembly interpreter, with the given Forth input program as input.
- While interpreting/compiling, WAForth generates new WebAssembly modules for each compiled word. When a new generated WebAssembly
  module is loaded into the WebAssembly runtime, `waforthc` keeps track of the raw binary form of the word.
- When WAForth is finished running the input program, some state is extracted from the runtime, so it can be restored later:
    - The current pointer to the dictionary entry of the compiled word (aka `latest`).
    - All the data between the initial data stack pointer and the current data stack pointer (which includes new dictionary entries, new strings, and
      any data stored in the data area)
- A new WAForth WebAssembly module is constructed, which replicates the state of the runtime after running the input program:
    - The IR representation of the embedded WAForth module is loaded using WABT's module reader
    - The IR representation of every raw binary WebAssembly module generated during compilation is 
      loaded using WABT's module reader. Every module contains 1 function (with 1 corresponding entry into the shared table). 
    - The function and table entry of each of these modules are appended to the WAForth module. 
      The index of the function is updated accordingly in the new module
    - A data segment is appended to the new WAForth module, containing the entire data stack portion recorded after compilation
    - The initializer expression of the global variables that contain the end-of-datastack pointer (`here`) and the pointer 
      to the latest dictionary entry (`latest`) are updated to reflect the new values
- The resulting WebAssembly module (containing the entire WAForth system, including all the newly compiled words and data) is converted to
  C using WABT's WebAssembly-to-C convertor. A [C runtime file](https://github.com/remko/waforth/blob/master/src/waforthc/rt.c) is also 
  generated to provide implementations of the I/O methods, and to drive the core's run loop.
  If an initial program is given to `waforthc`, this is also included statically into the source code, and used as the input for the new
  WAForth system (instead of the default, standard input).
- The resulting C program is compiled into a native executable using the platform's C compiler (`gcc`).


## Future work

Currently, all the compiler does is combine the modules generated by WAForth into a single module. It should be easy to do some post-processing on the resulting module to optimize the result:

- Compiled words use indirect calls to call other words. This causes significant execution overhead. Since in the resulting binary, all words are in the same WebAssembly module, all indirect calls in the generated modules can be replaced by direct calls.

- A dead-code elimination pass could remove unnecessary words from the
  WAForth core.

Instead of compiling the resulting module to native, it can also be used in e.g. the web environment. 
