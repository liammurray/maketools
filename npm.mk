# -*- mode: Makefile -*-
#
# Include file used to build projects with package.json
#
# Runs "npm run build" if any source file is out of date.
#

PATH := node_modules/.bin:$(PATH)

source_files := $(wildcard src/*.ts)
build_files := $(source_files:src/%.ts=dist/%.js)
# .package/<name>.tgz
PACKAGE := .package/$(shell node -p 'const p=require("./package.json"); `$${p.name}-$${p.version}.tgz`')

# For lerna: NPM_INSTALL=lerna bootstrap --scope <scope>
NPM_INSTALL?=npm install

.PHONY: \
	build \
	package \
  clean \
	lint \
  utest \
  server-develop \
  server-debug \
  watch

build: dist

package: $(PACKAGE)

clean:
	npm run compile:clean
	rm -f $(PACKAGE)

utest: node_modules dist
	npm run test

lint: node_modules
	npm run lint

# Make sure code is compiled, start server, watch for code changes
server-develop: dist
	npm run start:watch | pino-pretty

# Make sure code is compiled, start server (no watch) with inspector port
server-debug: dist
	npm run start:debug | pino-pretty

# Make sure code is compiled and watch for code changes
watch: dist
	npm run compile:watch

node_modules: package.json
	$(NPM_INSTALL) && touch node_modules

# For lambda functions
lambda: build
	npm run lambda

dist: $(source_files) node_modules tsconfig.json
	npm run compile

$(PACKAGE): $(build_files)
	@mkdir -p "$(dir $@)"
	cd $(dir $@) && npm pack $(CURDIR)/dist

