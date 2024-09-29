.DEFAULT_GOAL := all

VERSION?=$(shell cat ../../package.json | grep '"version"' | head -n 1 | sed -e 's/.*:.*"\(.*\)".*/\1/')

ifeq ($(OS),Windows_NT)
CXX = g++
WABT_DIR = /c/tools/wabt
WABT_INCLUDE_DIR ?= $(WABT_DIR)/include
WABT_LIB_DIR ?= $(WABT_DIR)/lib
WABT_DATA_DIR ?= $(WABT_DIR)/share/wabt
package: waforthc
	7z a -tzip waforthc-v$(VERSION)-windows.zip waforthc.exe
else # $(OS)
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
PACKAGE_SUFFIX=arm64-macos
else
PACKAGE_SUFFIX=x86_64-macos
endif
WABT_DIR = $(shell brew --prefix)
WABT_INCLUDE_DIR = $(WABT_DIR)/include
WABT_LIB_DIR = $(WABT_DIR)/lib
WABT_DATA_DIR = $(WABT_DIR)/share/wabt
LIBS := -mmacosx-version-min=13.0 
else # $(UNAME_S)
GCC_TARGET_MACHINE = $(shell gcc -dumpmachine)
WABT_DIR ?= /usr
WABT_INCLUDE_DIR ?= $(WABT_DIR)/include
WABT_LIB_DIR ?= $(WABT_DIR)/lib/$(GCC_TARGET_MACHINE)
WABT_DATA_DIR ?= $(WABT_DIR)/share/wabt
PACKAGE_SUFFIX=x86_64-linux
endif # $(UNAME_S)
package: waforthc
	$(TAR) czf waforthc-v$(VERSION)-$(PACKAGE_SUFFIX).tgz waforthc
endif # $(OS)

CXXFLAGS := -DVERSION='"$(VERSION)"' -Wall -std=c++17 -I$(WABT_INCLUDE_DIR) $(CXXFLAGS)
LIBS := -lwabt $(LIBS)
LDFLAGS := -L$(WABT_LIB_DIR)

ifeq ($(DEBUG),1)
CXXFLAGS := $(CXXFLAGS) -g
else
CXXFLAGS := $(CXXFLAGS) -O2
endif
ifeq ($(ASAN),1)
CXXFLAGS := $(CXXFLAGS) -fsanitize=address -fno-omit-frame-pointer
endif

# FIXME: Remove this when WABT #2071 is merged
CXXFLAGS := -DNDEBUG=1 $(CXXFLAGS)

BIN2H=../../scripts/bin2h
WAT2WASM=wat2wasm
WAT2WASM_FLAGS=--debug-names

OBJECTS := waforthc.o

all: waforthc

waforthc: $(OBJECTS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS) $(LIBS)

waforthc.o: waforth_core.h waforth_rt.h waforth_wabt_wasm-rt-impl_c.h waforth_wabt_wasm-rt-impl_h.h waforth_wabt_wasm-rt_h.h 

%.o: %.cpp
	$(CXX) -c $(CPPFLAGS) $(CXXFLAGS) -o $@ $<

waforth_core.h: waforth_core.wasm
	$(BIN2H) $< $@

waforth_rt.h: rt.c
	$(BIN2H) $< $@

waforth_wabt_wasm-rt-impl_c.h: $(WABT_DATA_DIR)/wasm2c/wasm-rt-impl.c
	$(BIN2H) $< $@

waforth_wabt_wasm-rt-impl_h.h: $(WABT_DATA_DIR)/wasm2c/wasm-rt-impl.h
	$(BIN2H) $< $@

waforth_wabt_wasm-rt_h.h: $(WABT_INCLUDE_DIR)/wasm-rt.h
	$(BIN2H) $< $@

waforth_core.wasm: ../waforth.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

.PHONY: package

sieve:
	./waforthc --ccflag=-O2 --output=sieve --init="90000000 sieve" ../examples/sieve.f

.PHONY: check
check:
	-rm -f test test.out
	./waforthc --output=test --init=SAY_HELLO ../examples/hello.fs | tee test.out
	grep -q "Hello, Forth" test.out
	./test | tee test.out
	grep -q "Hello, Forth" test.out
	-rm -f test test.out

.PHONY: clean
clean:
	-rm -rf waforthc *.exe *.o *.tgz *.zip \
	  waforth_core.wasm waforth_core.h \
	  waforth_rt.h \
	  waforth_wabt_wasm-rt-impl_c.h waforth_wabt_wasm-rt-impl_c.h waforth_wabt_wasm-rt_h.h waforth_wabt_wasm-rt-impl_h.h
