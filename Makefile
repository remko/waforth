WAT2WASM=wat2wasm
WAT2WASM_FLAGS=
ifeq ($(DEBUG),1)
WAT2WASM_FLAGS=--debug-names
endif
WEBPACK=npx webpack
WEBPACK_DEV_SERVER=npx webpack-dev-server

WASM_FILES=src/waforth.wasm tests/benchmarks/sieve-vanilla/sieve-vanilla.wasm

all: $(WASM_FILES)
	$(WEBPACK) --mode=production

dev-server: $(WASM_FILES)
	$(WEBPACK_DEV_SERVER) --open --openPage waforth --content-base public

wasm: $(WASM_FILES) src/tools/quadruple.wasm.hex

src/waforth.wasm: src/waforth.wat dist
	racket -f $< > src/waforth.wat.tmp
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ src/waforth.wat.tmp

tests/benchmarks/sieve-vanilla/sieve-vanilla.wasm: tests/benchmarks/sieve-vanilla/sieve-vanilla.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

dist:
	mkdir -p $@

src/tools/quadruple.wasm: src/tools/quadruple.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

src/tools/quadruple.wasm.hex: src/tools/quadruple.wasm
	hexdump -v -e '16/1 "_u%04X" "\n"' $< | sed 's/_/\\/g; s/\\u    //g; s/.*/    "&"/' > $@

clean:
	-rm -rf $(WASM_FILES) src/tools/quadruple.wasm src/tools/quadruple.wasm.hex src/waforth.wat.tmp dist
