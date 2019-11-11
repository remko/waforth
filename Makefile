WASM2WAT=wasm2wat
WAT2WASM=wat2wasm
WAT2WASM_FLAGS=
ifeq ($(DEBUG),1)
WAT2WASM_FLAGS:=$(WAT2WASM_FLAGS) --debug-names
endif

WASM_FILES=src/waforth.wasm src/waforth.bulkmem.wasm tests/benchmarks/sieve-vanilla.wasm

all: $(WASM_FILES)
	yarn -s build

dev-server: $(WASM_FILES)
	yarn -s dev-server

wasm: $(WASM_FILES) src/waforth.assembled.wat src/tools/quadruple.wasm.hex

process: src/waforth.vanilla.wat
	cp $< src/waforth.wat

src/waforth.wasm: src/waforth.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

src/waforth.vanilla.wat: src/waforth.wat
	./src/tools/process.js $< > $@

src/waforth.bulkmem.wasm: src/waforth.bulkmem.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) --enable-bulk-memory -o $@ $<

src/waforth.bulkmem.wat: src/waforth.wat
	./src/tools/process.js --enable-bulk-memory $< > $@

tests/benchmarks/sieve-vanilla.wasm: tests/benchmarks/sieve-vanilla.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

src/tools/quadruple.wasm: src/tools/quadruple.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

src/tools/quadruple.wasm.hex: src/tools/quadruple.wasm
	hexdump -v -e '16/1 "_u%04X" "\n"' $< | sed 's/_/\\/g; s/\\u    //g; s/.*/    "&"/' > $@

clean:
	-rm -rf $(WASM_FILES) src/tools/quadruple.wasm src/tools/quadruple.wasm.hex src/waforth.wat.tmp dist

check: $(WASM_FILES)
	yarn -s test

check-watch: $(WASM_FILES)
	yarn -s test-watch

lint:
	yarn -s lint
