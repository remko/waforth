# Standalone native WAForth executable

This directory contains a small C program to run the WAForth WebAssembly core
in a native WebAssembly engine.

The build currently uses the [Wasmtime](https://wasmtime.dev) engine,
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

## Download

You can download a pre-built binary of the standalone shell from 
[the Releases page](https://github.com/remko/waforth/releases).


## Building

Download dependencies (Wasmtime):

    make install-deps

Build:
  
    make
