.DEFAULT_GOAL := all

VERSION?=$(shell cat ../../../package.json | grep '"version"' | sed -e 's/.*:.*"\(.*\)".*/\1/')

ifeq ($(OS),Windows_NT)
CC=gcc
LIBS=
else
ifeq (, $(shell which gtar))
TAR := tar
else
# bsd-tar corrupts files on GitHub: https://github.com/actions/virtual-environments/issues/2619
TAR := gtar
endif
UNAME_S=$(shell uname -s)
UNAME_P=$(shell uname -p)
WABT_DIR = /usr/local/wabt
ifeq ($(UNAME_S),Darwin)
CXXFLAGS = -std=c++17
ifeq ($(UNAME_P),arm)
PACKAGE_SUFFIX=arm64-macos
else
PACKAGE_SUFFIX=x86_64-macos
endif
else
LIBS=-lpthread -lm -ldl
PACKAGE_SUFFIX=x86_64-linux
endif
package: waforth
	$(TAR) czf waforth-v$(VERSION)-$(PACKAGE_SUFFIX).tgz waforth
endif
WABT_INCLUDE_DIR := $(WABT_DIR)/include
WABT_LIB_DIR := $(WABT_DIR)/lib
CXXFLAGS:= -I$(WABT_INCLUDE_DIR) $(CXXFLAGS)
LIBS:=$(WABT_LIB_DIR)/libwabt.a $(LIBS)

ifeq ($(DEBUG),1)
CXXFLAGS := $(CXXFLAGS) -g
else
CXXFLAGS := $(CXXFLAGS) -O2
endif

################################################

BIN2H=../../../scripts/bin2h
WAT2WASM=wat2wasm
WAT2WASM_FLAGS=--debug-names

CXXFLAGS:=-DVERSION='"$(VERSION)"' $(CXXFLAGS)
OBJECTS=main.o $(RESOURCE_OBJECTS)

all: waforth

waforth: $(OBJECTS)
	$(CXX) $(CXXFLAGS) -o $@ $(OBJECTS) $(LDFLAGS) $(LIBS)

main.o: waforth_core.h

waforth_core.wasm: ../../waforth.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

waforth_core.h: waforth_core.wasm
	$(BIN2H) $< $@

.PHONY: package

run_sieve.f: ../../examples/sieve.f
	(cat $< && echo "90000000 sieve") > $@

.PHONY: run-sieve
run-sieve: run_sieve.f
	time ./waforth $<

.PHONY: check
check:
	-rm -f test.out
	echo ": MAIN 1 2 3 + .S ; MAIN" | ./waforth | tee test.out
	grep "1 5 ok" test.out
	rm test.out
	./waforth ../../examples/hello.fs | tee test.out
	grep "Hello, Forth" test.out
	rm test.out

	
.PHONY: clean
clean:
	-rm -f waforth_core.wasm waforth_core.h $(OBJECTS) waforth *.exe *.tgz *.zip test.out
