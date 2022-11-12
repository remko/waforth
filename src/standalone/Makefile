.DEFAULT_GOAL := all

VERSION?=$(shell cat ../../package.json | grep '"version"' | sed -e 's/.*:.*"\(.*\)".*/\1/')

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
ifeq ($(OS),Windows_NT)

WASMTIME_DIR=wasmtime-v1.0.0-x86_64-mingw-c-api
WASMTIME_RELEASE_URL=https://github.com/bytecodealliance/wasmtime/releases/download/v1.0.0/wasmtime-v1.0.0-x86_64-mingw-c-api.zip
CC=gcc
CFLAGS=-DWASM_API_EXTERN=
LIBS=-luserenv -lole32 -lntdll -lws2_32 -lkernel32 -lbcrypt
RESOURCE_OBJECTS=waforth.res

install-deps:
	-rm -rf wasmtime-*
	curl -o $(WASMTIME_DIR).zip -L -s $(WASMTIME_RELEASE_URL)
	unzip $(WASMTIME_DIR).zip

package: waforth
	7z a -tzip waforth-v$(VERSION)-windows.zip waforth.exe

comma:=,
%.res: %.rc
	windres --use-temp-file $< -DVERSION_STRING='"$(VERSION)"' -DVERSION_TUPLE='$(subst .,$(comma),$(VERSION)),0' -O coff -o $@

else

ifeq (, $(shell which gtar))
TAR := tar
else
# bsd-tar corrupts files on GitHub: https://github.com/actions/virtual-environments/issues/2619
TAR := gtar
endif
UNAME_S=$(shell uname -s)
UNAME_P=$(shell uname -p)
ifeq ($(UNAME_S),Darwin)
ifeq ($(UNAME_P),arm)
WASMTIME_DIR=wasmtime-v1.0.1-aarch64-macos-c-api
PACKAGE_SUFFIX=arm64-macos
else
WASMTIME_DIR=wasmtime-v1.0.1-x86_64-macos-c-api
PACKAGE_SUFFIX=x86_64-macos
endif
WASMTIME_RELEASE_URL=https://github.com/bytecodealliance/wasmtime/releases/download/v1.0.1/$(WASMTIME_DIR).tar.xz
else
WASMTIME_DIR=wasmtime-v1.0.1-x86_64-linux-c-api
WASMTIME_RELEASE_URL=https://github.com/bytecodealliance/wasmtime/releases/download/v1.0.1/wasmtime-v1.0.1-x86_64-linux-c-api.tar.xz
LIBS=-lpthread -lm -ldl
PACKAGE_SUFFIX=x86_64-linux
endif

install-deps:
	-rm -rf wasmtime-*
	curl -L -s $(WASMTIME_RELEASE_URL) | tar xJv

package: waforth
	$(TAR) czf waforth-v$(VERSION)-$(PACKAGE_SUFFIX).tgz waforth

endif
endif
CFLAGS:=-I$(WASMTIME_DIR)/include $(CFLAGS)
LIBS:=$(WASMTIME_DIR)/lib/libwasmtime.a $(LIBS)

################################################

BIN2H=../../scripts/bin2h
WAT2WASM=wat2wasm
WAT2WASM_FLAGS=--debug-names

CFLAGS:=-DVERSION='"$(VERSION)"' $(CFLAGS)
OBJECTS=main.o $(RESOURCE_OBJECTS)

all: waforth

waforth: $(OBJECTS)
	$(CC) -o $@ $(OBJECTS) $(LDFLAGS) $(LIBS)

main.o: waforth_core.h

icon.ico: ../../doc/logo.svg
	convert -background transparent $< -define icon:auto-resize=16,32,48,64,256 $@

waforth_core.wasm: ../waforth.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

waforth_core.h: waforth_core.wasm
	$(BIN2H) $< $@

.PHONY: install-deps package

.PHONY: check
check:
	-rm -f test.out
	echo ": MAIN 1 2 3 + .S ; MAIN" | ./waforth | tee test.out
	grep "1 5 ok" test.out
	rm test.out
	./waforth ../examples/hello.fs | tee test.out
	grep "Hello, Forth" test.out
	rm test.out

	
.PHONY: clean
clean:
	-rm -f waforth_core.wasm waforth_core.h $(OBJECTS) waforth *.tgz *.zip test.out
