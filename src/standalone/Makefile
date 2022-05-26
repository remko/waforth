UNAME_S=$(shell uname -s)
UNAME_P=$(shell uname -p)

.DEFAULT_GOAL := all

################################################
# WebAssembly engine configuration
################################################

# Wasmer (https://wasmer.io)
# WARNING! Loading compiled words does not work
ifeq ($(WASMER),1)
WASMER_DIR=$(HOME)/.wasmer
CFLAGS=-I$(WASMER_DIR)/include
LIBS:=$(WASMER_DIR)/lib/libwasmer.a
else

# Wasmtime (https://wasmtime.dev)
ifeq ($(UNAME_S),Darwin)
WASMTIME_DIR=wasmtime-v0.37.0-x86_64-macos-c-api
WASMTIME_RELEASE_URL=https://github.com/bytecodealliance/wasmtime/releases/download/v0.37.0/wasmtime-v0.37.0-x86_64-macos-c-api.tar.xz
else
WASMTIME_DIR=wasmtime-v0.37.0-x86_64-linux-c-api
WASMTIME_RELEASE_URL=https://github.com/bytecodealliance/wasmtime/releases/download/v0.37.0/wasmtime-v0.37.0-x86_64-linux-c-api.tar.xz
LIBS=-lpthread -lm -ldl
endif
CFLAGS=-I$(WASMTIME_DIR)/include
LIBS:=$(WASMTIME_DIR)/lib/libwasmtime.a $(LIBS)

install-deps:
	-rm -rf wasmtime-*
	curl -L -s $(WASMTIME_RELEASE_URL) | tar xJv
endif

################################################

ifeq ($(UNAME_S),Darwin)
PACKAGE_SUFFIX=x86_64-macos
else
PACKAGE_SUFFIX=x86_64-linux
endif

VERSION?=$(shell cat ../../package.json | grep '"version"' | sed -e 's/.*:.*"\(.*\)".*/\1/')
BIN2H=../../scripts/bin2h
WAT2WASM=wat2wasm
WAT2WASM_FLAGS=--debug-names

CFLAGS:=-DVERSION='"$(VERSION)"' $(CFLAGS)
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

.PHONY: package
package: waforth
	tar czf waforth-v$(VERSION)-$(PACKAGE_SUFFIX).tgz waforth

.PHONY: clean
clean:
	-rm -f waforth_core.wasm waforth_core.h $(OBJECTS) waforth *.tgz
