fetch("sieve-vanilla.wasm")
  .then(resp => resp.arrayBuffer())
  .then(module =>
    WebAssembly.instantiate(module, {
      js: {
        print: x => console.log(x)
      }
    })
  )
  .then(instance => {
    window.sieve = instance.instance.exports.sieve;
  });
