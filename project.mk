# -*- mode: Makefile -*-
#

SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
include $(SELF_DIR)util.mk

# List of targets that are not files
.PHONY: \
	build-src \
	build-lambda \
	build-layer \
	clean-projects \
	list \
	test \
	lint \
	clean \
	build \

LAYER_DIR ?= ./layer
FUNCS_DIR ?= ./funcs

SHELL=/usr/bin/env bash -o pipefail

# Locate makefiles under $FUNCS_DIR
makefiles = $(shell export GLOBIGNORE=".$(FUNCS_DIR)/ignore/.*" ; echo $(FUNCS_DIR)/*/makefile)
subdirs := $(foreach proj,$(makefiles),$(dir $(proj)))

list:
	@echo -------Funcs-----------
	@for dir in $(subdirs); do echo $$dir ; done
	@echo -------Targets-----------
	@(make -qp || true) | grep -v '^list$$' | awk -F':' '/^[a-zA-Z0-9][^$$#\/\t=]*:([^=]|$$)/ {split($$1,A,/ /);for(i in A)print A[i]}' | sort


build-src:
	@for dir in $(subdirs); do \
		$(MAKE) -C $$dir build; \
	 done

build-lambda:
	@echo "Building lambdas... [$(subdirs)]"
	@for dir in $(subdirs); do \
		$(MAKE) -C $$dir lambda; \
	 done

ifneq "$(wildcard $$LAYER_DIR)" ""

build-layer:
	@echo "Building layer(s)..."
	$(MAKE) -C $$LAYER_DIR/nodejs build

clean-layer:
	$(MAKE) -C $$LAYER_DIR/nodejs clean

endif

clean-projects:
	@for dir in $(subdirs); do \
		$(MAKE) -C $$dir clean; \
	 done

test:
	@set -e; for dir in $(subdirs); do \
		cd $$dir; \
		npm run test; \
	 done

lint:
	@set -e; for dir in $(subdirs); do \
		cd $$dir; \
		npm run lint; \
	 done

clean: clean-projects clean-layer


# Add build-layer as dependency if ./layer exists
BUILD_DEPS = build-lambda
ifneq "$(wildcard ./layer)" ""
BUILD_DEPS += build-layer
endif

build: $(BUILD_DEPS)

