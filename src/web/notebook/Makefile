all:
	./build.js

dev:
	./build.js --development --watch

.PHONY: example
example:
	../../../dist/wafnb2html examples/drawing-with-forth.wafnb
	
clean:
	-rm -rf dist