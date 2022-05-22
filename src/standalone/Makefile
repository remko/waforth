WAMR_DIR=wasm-micro-runtime
CC=clang
CFLAGS=-I$(WAMR_DIR)/core/iwasm/include -DWASM_ENABLE_DEBUG_INTERP
LDFLAGS=-L$(WAMR_DIR)/product-mini/platforms/darwin/build -rpath $(WAMR_DIR)/product-mini/platforms/darwin/build
LIBS=-liwasm

BIN2H=../../scripts/bin2h
WAT2WASM=wat2wasm

OBJECTS=main.o

all: $(OBJECTS)
	$(CC) -o waforth $(OBJECTS) $(LDFLAGS) $(LIBS)

main.o: waforth_core.h

waforth_core.wasm: ../waforth.wat
	$(WAT2WASM) $(WAT2WASM_FLAGS) -o $@ $<

waforth_core.h: waforth_core.wasm
	$(BIN2H) ../waforth.wasm waforth_core.h 