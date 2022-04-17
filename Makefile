WASM2WAT=wasm2wat
WAT2WASM=wat2wasm
WAT2WASM_FLAGS=
ifeq ($(DEBUG),1)
WAT2WASM_FLAGS:=$(WAT2WASM_FLAGS) --debug-names
endif

all:
	yarn -s build

dev:
	yarn -s dev

check:
	yarn -s test

check-watch:
	yarn -s test-watch

lint:
	yarn -s lint

wasm: src/waforth.assembled.wat scripts/quadruple.wasm.hex

process: src/waforth.vanilla.wat
	cp $< src/waforth.wat

src/waforth.wasm: src/waforth.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

src/waforth.vanilla.wat: src/waforth.wat
	./scripts/process.js $< $@

src/waforth.bulkmem.wasm: src/waforth.bulkmem.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) --enable-bulk-memory -o $@ $<

src/waforth.bulkmem.wat: src/waforth.wat
	./scripts/process.js --enable-bulk-memory $< $@

src/benchmarks/sieve-vanilla.wasm: src/benchmarks/sieve-vanilla.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

scripts/quadruple.wasm: scripts/quadruple.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

scripts/quadruple.wasm.hex: scripts/quadruple.wasm
	hexdump -v -e '16/1 "_u%04X" "\n"' $< | sed 's/_/\\/g; s/\\u    //g; s/.*/    "&"/' > $@

clean:
	-rm -rf $(WASM_FILES) scripts/quadruple.wasm scripts/quadruple.wasm.hex src/waforth.wat.tmp dist

