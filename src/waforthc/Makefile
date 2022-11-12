ifeq ($(OS),Windows_NT)

else
UNAME_S=$(shell uname -s)
UNAME_P=$(shell uname -p)
ifeq ($(UNAME_S),Darwin)
# FIXME: When new WABT 1.0.31 is released, we can update this to standard paths
WABT_INCLUDE_DIR := $(HOME)/Downloads/src/wabt/include
WABT_LIB_DIR := $(HOME)/Downloads/src/wabt/build
WABT_WASM2C_SRC_DIR = $(HOME)/Downloads/src/wabt/wasm2c
# BOOST_INCLUDE_DIR := /opt/homebrew/include
# BOOST_LIB_DIR := /opt/homebrew/lib
BOOST_INCLUDE_DIR = /opt/homebrew/Cellar/boost/1.80.0/include
BOOST_LIB_DIR := /opt/homebrew/Cellar/boost/1.80.0/lib
LIBS := -mmacosx-version-min=13.0 
CXXFLAGS := -std=c++20
else
WABT_INCLUDE_DIR := /usr/local/wabt/include
WABT_LIB_DIR := /usr/local/wabt/lib
WABT_WASM2C_SRC_DIR = /usr/local/wasm2c
BOOST_INCLUDE_DIR = /usr/include
BOOST_LIB_DIR := /usr/lib/x86_64-linux-gnu
endif
LIBS := -L$(WABT_LIB_DIR) -lwabt $(BOOST_LIB_DIR)/libboost_filesystem.a $(BOOST_LIB_DIR)/libboost_program_options.a $(LIBS)
CXXFLAGS := $(CXXFLAGS) -g 
endif

CPPFLAGS := -g \
	-I$(WABT_INCLUDE_DIR) \
	-I$(BOOST_INCLUDE_DIR)

BIN2H=../../scripts/bin2h
WAT2WASM=wat2wasm
WAT2WASM_FLAGS=--debug-names

OBJECTS := waforthc.o

all: waforthc

waforthc: $(OBJECTS)
	$(CXX) -o $@ $^ $(LIBS)

waforthc.o: waforth_core.h waforth_rt.h waforth_wabt_wasm-rt-impl_c.h waforth_wabt_wasm-rt-impl_h.h waforth_wabt_wasm-rt_h.h 

%.o: %.cpp
	$(CXX) -c $(CPPFLAGS) $(CXXFLAGS) -o $@ $<

waforth_core.h: waforth_core.wasm
	$(BIN2H) $< $@

waforth_rt.h: rt.c
	$(BIN2H) $< $@

waforth_wabt_wasm-rt-impl_c.h: $(WABT_WASM2C_SRC_DIR)/wasm-rt-impl.c
	$(BIN2H) $< $@

waforth_wabt_wasm-rt-impl_h.h: $(WABT_WASM2C_SRC_DIR)/wasm-rt-impl.h
	$(BIN2H) $< $@

waforth_wabt_wasm-rt_h.h: $(WABT_WASM2C_SRC_DIR)/wasm-rt.h
	$(BIN2H) $< $@

waforth_core.wasm: ../waforth.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

clean:
	-rm -rf waforthc waforth_core.wasm waforth_core.h waforth_rt.h waforth_wabt_wasm-rt-impl_c.h waforth_wabt_wasm-rt-impl_c.h waforth_wabt_wasm-rt_h.h waforth_wabt_wasm-rt-impl_h.h waforth *.o _waforth*
