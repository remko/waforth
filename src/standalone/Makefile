WASMTIME_DIR=wasmtime-v0.37.0-x86_64-macos-c-api
WASMTIME_RELEASE_URL=https://github.com/bytecodealliance/wasmtime/releases/download/v0.37.0/wasmtime-v0.37.0-x86_64-macos-c-api.tar.xz

CFLAGS=-I$(WASMTIME_DIR)/include
LDFLAGS=
LIBS=$(WASMTIME_DIR)/lib/libwasmtime.a

BIN2H=../../scripts/bin2h
WAT2WASM=wat2wasm
WAT2WASM_FLAGS=--debug-names

OBJECTS=main.o

all: waforth

waforth: $(OBJECTS)
	$(CC) -o $@ $(OBJECTS) $(LDFLAGS) $(LIBS)

main.o: waforth_core.h

waforth_core.wasm: ../waforth.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

waforth_core.h: waforth_core.wasm
	$(BIN2H) $< $@

.PHONY: install-deps
install-deps:
	-rm -rf wasmtime-*
	curl -L -s $(WASMTIME_RELEASE_URL) | tar xvz 


.PHONY: clean
clean:
	-rm -f waforth_core.wasm waforth_core.h $(OBJECTS) waforth
