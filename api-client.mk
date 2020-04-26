# -*- mode: Makefile -*-
#

SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

include $(SELF_DIR)/util.mk

$(call check_defined, STACK_NAME, stack name)
$(call check_defined, GEN_DIR, generated output directory)
$(call check_defined, CLIENT_CONFIG_DIR, openapi generator config base directory)

# For openapi-generator (ordersapi-generator list to see others)
# You can change this and run "make client" to experiment
CLIENT_TYPE ?= typescript-axios
CLIENT_NAME ?= $(STACK_NAME)-client-axios
CLIENT_CONFIG = $(CLIENT_CONFIG_DIR)/$(CLIENT_NAME).yaml
CLIENT_OUTPUT_DIR = $(GEN_DIR)/$(CLIENT_NAME)

SWAGGER_BASE_NAME=$(STACK_NAME)-api
SWAGGER_FILE=$(GEN_DIR)/$(SWAGGER_BASE_NAME).yaml

# List of targets that are not files
.PHONY: \
	swagger \
	client \
	clean \
	publish \
	push \
	fixup

$(SWAGGER_FILE):
	@mkdir -p $(GEN_DIR)
	@$(MAKETOOLS)/py3/stack.py swagger -d $(GEN_DIR) -e none $(STACK_NAME)

swagger: $(SWAGGER_FILE)

# https://openapi-generator.tech/docs/generators/typescript-axios
#
# Requires prettier installed globally: npm i -g prettier
#

$(CLIENT_OUTPUT_DIR): $(SWAGGER_FILE) $(CLIENT_CONFIG)
	@echo "Generating $(CLIENT_OUTPUT_DIR)..."
	@mkdir -p $(dir $@)
	@export TS_POST_PROCESS_FILE="/usr/local/bin/prettier --write"; \
	openapi-generator generate -i $(SWAGGER_FILE) \
		-c $(CLIENT_CONFIG) -g $(CLIENT_TYPE) -o $(CLIENT_OUTPUT_DIR)

# Add "respository" so github repo and scope match.
#
# jq '.repository = "github:liammurray/orders-client-axios"' package.json|sponge package.json
#
# Add "files" for publish
#
fixup: $(CLIENT_OUTPUT_DIR)
	@echo "Fixing up package.json in $(CLIENT_OUTPUT_DIR)..."
	@cd $(CLIENT_OUTPUT_DIR) && \
		jq '.repository = "$(CLIENT_GITHUB_REPO)"' package.json|sponge package.json && \
		jq '.files = ["dist", "package.json"]' package.json|sponge package.json


# Generate client sdk (openapi-generator)
client: $(CLIENT_OUTPUT_DIR) fixup

clean:
	@echo "Removing generated client..."
	@rm -rf $(CLIENT_OUTPUT_DIR)

dist: client
	@echo "Building client in $(CLIENT_OUTPUT_DIR)..."
	@cd $(CLIENT_OUTPUT_DIR) && \
		npm i && npm run build

