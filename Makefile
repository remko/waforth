WASM2WAT=wasm2wat
WAT2WASM=wat2wasm
WAT2WASM_FLAGS=
ifeq ($(DEBUG),1)
WAT2WASM_FLAGS=--debug-names
endif

WASM_FILES=src/waforth.wasm tests/benchmarks/sieve-vanilla.wasm

all: $(WASM_FILES)
	yarn -s build

dev-server: $(WASM_FILES)
	yarn -s dev-server

wasm: $(WASM_FILES) src/waforth.assembled.wat src/tools/quadruple.wasm.hex

src/waforth.wasm: src/waforth.wat dist
	racket -f $< > src/waforth.wat.tmp
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ src/waforth.wat.tmp

src/waforth.assembled.wat: src/waforth.wasm
	$(WASM2WAT) --fold-exprs --inline-imports --inline-exports -o $@ $<

tests/benchmarks/sieve-vanilla.wasm: tests/benchmarks/sieve-vanilla.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

dist:
	mkdir -p $@

src/tools/quadruple.wasm: src/tools/quadruple.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

src/tools/quadruple.wasm.hex: src/tools/quadruple.wasm
	hexdump -v -e '16/1 "_u%04X" "\n"' $< | sed 's/_/\\/g; s/\\u    //g; s/.*/    "&"/' > $@

clean:
	-rm -rf $(WASM_FILES) src/tools/quadruple.wasm src/tools/quadruple.wasm.hex src/waforth.wat.tmp dist

check:
	yarn -s test

lint:
	yarn -s lint
