CFLAGS=
CPPFLAGS=-I. -Iwaforth.gen -Iwasm2c
LINKFLAGS=-g

.DEFAULT_GOAL := all

-include waforth.gen/Makefile.inc

OBJECTS=waforth_core.o main.o waforth.o wasm2c/wasm-rt-impl.o $(WAFORTH_MODULE_OBJECTS)

.PHONY: all
all: main

.PHONY: example
example:
	./waforth2c.js examples/sieve.f
	$(MAKE) 
	./main
	
main: $(OBJECTS)
	$(CC) $(LINKFLAGS) -o $@ $(OBJECTS)

clean:
	-rm -rf $(OBJECTS) waforth_core.c waforth_core.h main $(WAFORTH_MODULE_HEADERS) $(WAFORTH_MODULE_SOURCES)

waforth.o: waforth.gen/waforth_modules.h

waforth_core.c: ../../src/waforth.wasm
	wasm2c $< -o $@

waforth_core.o: waforth_core.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -DWASM_RT_MODULE_PREFIX=waforth_core_ -c $< -o $@

