# WAForth2C: Experiment to use WAForth to convert Forth to C

Uses WAForth to generate WebAssembly modules, passes them to `wasm2c`, and
compiles and loads everything together into a native binary.

## Usage

1. Create a `.f` file with a `main` word defined (e.g. `example/sieve.f`)
2. Compile

        ./waforth2c.js examples/sieve.f

    This will generate `.wasm` files for all the defined words.

3. Build

        make

    This will generate `.c` files from the `.wasm` files generated in 2., and build
    them using the C compiler.

4. Run

        ./main
