.PHONY: help build build-native clean install test run check fmt compare

NIM ?= nim
ROOT_DIR := ..
BINARY ?= $(ROOT_DIR)/bin/sysfetch

help:
	@echo "sysfetch Nim build targets"
	@echo "  make build        - build an optimized local binary"
	@echo "  make build-native - build and copy the native binary to release/"
	@echo "  make check        - type-check the Nim source"
	@echo "  make test         - type-check the Nim source"
	@echo "  make run          - run the human-readable display"
	@echo "  make compare      - compare default output with official Neofetch"
	@echo "  make clean        - remove generated binaries"

build:
	mkdir -p $(ROOT_DIR)/bin
	$(NIM) c -d:release -o:$(BINARY) sysfetch.nim

build-native:
	./build-native.sh

check:
	$(NIM) check sysfetch.nim

test: check

run:
	$(NIM) r -d:release sysfetch.nim

install: build
	install -m 755 $(BINARY) "$(HOME)/.local/bin/sysfetch"

fmt:
	nimpretty --backup:off sysfetch.nim

compare: build
	./compare-neofetch.sh

clean:
	trash $(ROOT_DIR)/bin/sysfetch nimcache $(ROOT_DIR)/release
