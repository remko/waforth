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

wasm: src/waforth.assembled.wat scripts/word.wasm.hex

src/web/benchmarks/sieve/sieve-c.js:
	emcc src/web/benchmarks/sieve/sieve.c -O2 -o $@ \
		-sSINGLE_FILE -sMODULARIZE -sINITIAL_MEMORY=100Mb \
		-sEXPORTED_FUNCTIONS=_sieve -sEXPORTED_RUNTIME_METHODS=ccall,cwrap

.PHONY: standalone
standalone:
	$(MAKE) -C src/standalone

.PHONY: waforthc
waforthc:
	$(MAKE) -C src/waforthc

%.wasm: %.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

%.wasm.hex: %.wasm
	hexdump -v -e '16/1 "_%02X" "\n"' $< | sed 's/_/\\/g; s/\\u    //g; s/.*/    "&"/' > $@

clean:
	-rm -rf $(WASM_FILES) scripts/word.wasm scripts/word.wasm.hex src/waforth.wat.tmp \
		public/waforth run_sieve.*


################################################################################
# Sieve benchmark
################################################################################

run_sieve.c: src/web/benchmarks/sieve/sieve.c
	(echo "#include <stdio.h>" && cat $< && echo "int main() { printf(\"%d\\\n\", sieve(90000000)); return 0; }") > $@

run_sieve: run_sieve.c
	$(CC) -O2 -o $@ $<

run-sieve: run_sieve
	time ./run_sieve

run-sieve-gforth:
	time gforth -m 100000 src/examples/sieve.f -e "90000000 sieve bye"

run-sieve-gforth-fast:
	time gforth-fast -m 100000 src/examples/sieve.f -e "90000000 sieve bye"

