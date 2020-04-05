# -*- mode: Makefile -*-
#

SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))


include $(SELF_DIR)util.mk

$(call check_defined, STACK_NAME, stack name)
$(call check_defined, GEN_DIR, generated output directory)
$(call check_defined, GIT_TOKEN, github token for client push)
$(call check_defined, GITHUB_OWNER, github owner for client push)
$(call check_defined, SWAGGER_FILE, swagger file used to generate client)
$(call check_defined, CLIENT_CONFIG_DIR, openapi generator config base directory)

# For openapi-generator (ordersapi-generator list to see others)
# You can change this and run "make client" to experiment
CLIENT_TYPE = typescript-axios
CLIENT_NAME = $(STACK_NAME)-client-axios
CLIENT_CONFIG = $(CLIENT_CONFIG_DIR)/$(CLIENT_NAME).yaml
CLIENT_OUTPUT_DIR = $(GEN_DIR)/$(CLIENT_NAME)
CLIENT_MSG?="Update openapi client"
CLIENT_GITHUB_REPO=github:$(GITHUB_OWNER)/$(CLIENT_NAME)

# List of targets that are not files
.PHONY: \
	client \
	client-clean \
	client-publish \
	client-push \
	client-fixup


# https://openapi-generator.tech/docs/generators/typescript-axios
#
# Requires prettier installed globally: npm i -g prettier
#

$(CLIENT_OUTPUT_DIR): $(SWAGGER_FILE) $(CLIENT_CONFIG)
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
client-fixup: $(CLIENT_OUTPUT_DIR)
	cd $(CLIENT_OUTPUT_DIR) && \
		jq '.repository = "$(CLIENT_GITHUB_REPO)"' package.json|sponge package.json && \
		jq '.files = ["dist", "package.json"]' package.json|sponge package.json


# Generate client sdk (openapi-generator)
client: $(CLIENT_OUTPUT_DIR) client-fixup
client-clean:
	@rm -rf $(CLIENT_OUTPUT_DIR)

client-dist: client
	cd $(CLIENT_OUTPUT_DIR) && \
		npm i && npm run build

#
# Only push when publishing a new package
#
# For unrelated history issues, etc. (need to fix this) use this work-around
#
# git pull --allow-unrelated-histories origin master
# git co --ours .
# git commit -m "Update scope and repo"
# git push --set-upstream origin master
#
# To publish:
#   npm publish
#
client-push: client
	cd $(CLIENT_OUTPUT_DIR) && \
		export GIT_TOKEN ; /bin/sh ./git_push.sh $(GITHUB_OWNER) $(CLIENT_NAME) $(CLIENT_MSG) "github.com"

