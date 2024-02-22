all:
	./build.js

.PHONY: install-deps
install-deps:
	npm install --global vsce

.PHONY: prepackage
prepackage: all LICENSE.txt icon.png

.PHONY: package
package:
	vsce package

.PHONY: publish
publish:
	vsce publish

LICENSE.txt: ../../../LICENSE.txt
	cp $^ $@

icon.png: ../../../doc/logo.svg
	convert -background transparent $< $@

.PHONY: clean
clean:
	-rm -rf dist LICENSE.txt *.vsix icon.png
