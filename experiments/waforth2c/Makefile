CFLAGS=
CPPFLAGS=-Wno-main-return-type -Wno-main -I. -Iwaforth.gen -Iwasm2c
LINKFLAGS=-g

.DEFAULT_GOAL := all

-include waforth.gen/Makefile.inc

WAFORTH_MODULE_SOURCES=$(patsubst %.wasm,%.c,$(WAFORTH_MODULES))
WAFORTH_MODULE_HEADERS=$(patsubst %.wasm,%.h,$(WAFORTH_MODULES))
WAFORTH_MODULE_OBJECTS=$(patsubst %.wasm,%.o,$(WAFORTH_MODULES))

OBJECTS=waforth_core.o main.o waforth.o wasm2c/wasm-rt-impl.o $(WAFORTH_MODULE_OBJECTS) waforth.gen/waforth_modules.o

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

waforth.gen/waforth_module_%.c waforth.gen/waforth_module_%.h: waforth.gen/waforth_module_%.wasm
	wasm2c $< -o $(subst .wasm,.c,$<)

waforth.gen/waforth_module_%.wasm: waforth.gen/waforth_module_%.in.wasm
	wasm-dis $< -o $(subst .wasm,.wat,$@)
	wasm-as $(subst .wasm,.wat,$@) -o $@

waforth.gen/waforth_module_%.o: waforth.gen/waforth_module_%.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -DWASM_RT_MODULE_PREFIX=$(subst waforth.gen/,,$(subst .o,,$@))_ -c $< -o $@

waforth.gen/waforth_modules.h: $(WAFORTH_MODULE_HEADERS)
