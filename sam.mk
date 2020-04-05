# -*- mode: Makefile -*-
#

SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

# To override
#override MYVAR := someval
#include....

include $(SELF_DIR)util.mk


# Generated output (should .gitignore)
GEN_DIR ?= generated
$(call check_defined, SCRIPTS_DIR, script dir [common utils])


#
# SAM stuff
#
$(call check_defined, STACK_NAME, stack name)
$(call check_defined, PACKAGE_OUTPUT_BUCKET, lambda output bucket)
SAM_BUILD_OUTPUT_TEMPLATE = $(GEN_DIR)/.packaged.yaml

export CFN_OUTPUTS=$(GEN_DIR)/.cfn-outputs.json

#
# OpenAPI client stuff
#
$(call check_defined, GIT_TOKEN, github token for client push)
$(call check_defined, GITHUB_OWNER, github owner for client push)

# For openapi-generator (ordersapi-generator list to see others)
# You can change this and run "make client" to experiment
CLIENT_TYPE = typescript-axios
CLIENT_SUFFIX = axios
# e.g. "orders-client-axios"
CLIENT_NAME = $(STACK_NAME)-client-$(CLIENT_SUFFIX)
CLIENT_OUTPUT_DIR = $(GEN_DIR)/$(CLIENT_NAME)
CLIENT_MSG?="Update openapi client"
# github:liammurray/orders-client-axios
CLIENT_GITHUB_REPO=github:$(GITHUB_OWNER)/$(CLIENT_NAME)
# Prefix (orders becomes orders-api.yml)
SWAGGER_NAME=$(STACK_NAME)-api

# List of targets that are not files
.PHONY: \
	list \
	build-src \
	build-lambda \
	build-layer \
	clean-projects \
	test \
	clean \
	build \
	api \
	validate \
	package \
	deploy \
	deploy-sam \
	errors \
	generated-clean \
	output \
	output-table \
	swagger \
	client \
	client-clean \
	client-publish \
	client-push \
	client-fixup

SHELL=/usr/bin/env bash -o pipefail

# Locate makefiles under ./funcs
makefiles = $(shell export GLOBIGNORE="./funcs/ignore/.*" ; echo ./funcs/*/makefile)
subdirs := $(foreach proj,$(makefiles),$(dir $(proj)))

list:
	@echo Stack name: $(STACK_NAME)
	@echo Subdirs: $(subdirs)
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

build-layer:
	@echo "Building layer(s)..."
	$(MAKE) -C ./layer/nodejs build

clean-layer:
	$(MAKE) -C ./layer/nodejs clean

clean-projects:
	@for dir in $(subdirs); do \
		$(MAKE) -C $$dir clean; \
	 done

test:
	@set -e; for dir in $(subdirs); do \
		cd $$dir; \
		npm run test; \
	 done

clean: clean-projects clean-layer
	@rm -rf .aws-sam
	@rm -f $$SAM_BUILD_OUTPUT_TEMPLATE


# Add build-layer as dependency if ./layer exists
BUILD_DEPS = build-lambda
ifneq "$(wildcard ./layer)" ""
BUILD_DEPS += build-layer
endif

build: $(BUILD_DEPS)

local-api:
	sam local start-api

validate:
	sam validate

# Not used since 'sam build' redudantly re-installs
# packages for each function from same directory.
#
# $(SAM_BUILD_OUTPUT_TEMPLATE): .aws-sam/build
# 	sam package \
# 		--output-template-file $(SAM_BUILD_OUTPUT_TEMPLATE) \
# 	  --s3-bucket $(PACKAGE_OUTPUT_BUCKET)
#

$(SAM_BUILD_OUTPUT_TEMPLATE): build
	sam package \
		--output-template-file $(SAM_BUILD_OUTPUT_TEMPLATE) \
	  --s3-bucket $(PACKAGE_OUTPUT_BUCKET)

package: $(SAM_BUILD_OUTPUT_TEMPLATE)


deploy-sam: $(SAM_BUILD_OUTPUT_TEMPLATE)
	sam deploy \
		--template-file $(SAM_BUILD_OUTPUT_TEMPLATE) \
		--stack-name $(STACK_NAME) \
		--capabilities CAPABILITY_NAMED_IAM

deploy: deploy-sam swagger

# changeset: $(SAM_BUILD_OUTPUT_TEMPLATE)
# 	@aws cloudformation deploy \
# 		--no-execute-changeset \
# 		--template-file $(SAM_BUILD_OUTPUT_TEMPLATE) \
# 		--stack-name $(STACK_NAME) \
# 		--capabilities CAPABILITY_NAMED_IAM

destroy:
	aws cloudformation delete-stack \
			--stack-name $(STACK_NAME)

errors:
	@aws cloudformation describe-stack-events \
			--stack-name $(STACK_NAME) \
			| jq '.StackEvents[]|select(.ResourceStatus|index("FAILED"))'

output-table:
	aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) \
		--query 'Stacks[].Outputs' \
		--output table

output:
	aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) | jq '.Stacks[].Outputs'

$(GEN_DIR):
	@mkdir -p $@

generated-clean:
	@rm -rf $(GEN_DIR)

$(CFN_OUTPUTS):
	@mkdir -p $(dir $@)
	@$(SCRIPTS_DIR)/cache-outputs.sh $(STACK_NAME)

$(GEN_DIR)/$(SWAGGER_NAME)-postman.yml: $(CFN_OUTPUTS)
	@mkdir -p $(dir $@)
	@$(SCRIPTS_DIR)/get-swagger.sh -o $(GEN_DIR) $(STACK_NAME) postman

$(GEN_DIR)/$(SWAGGER_NAME).yml:  $(CFN_OUTPUTS)
	@mkdir -p $(dir $@)
	@$(SCRIPTS_DIR)/get-swagger.sh -o $(GEN_DIR) $(STACK_NAME) swagger

# https://openapi-generator.tech/docs/generators/typescript-axios
#
# Requires prettier installed globally: npm i -g prettier
#

$(CLIENT_OUTPUT_DIR): $(GEN_DIR)/$(SWAGGER_NAME).yml ./tools/$(CLIENT_NAME).yaml
	@mkdir -p $(dir $@)
	@export TS_POST_PROCESS_FILE="/usr/local/bin/prettier --write"; \
	cd $(CLIENT_OUTPUT_DIR) && openapi-generator generate -i $(SWAGGER_NAME).yml \
		-c ../tools/$(CLIENT_NAME).yaml \
		-g $(CLIENT_TYPE) -o $(CLIENT_NAME)

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


# Generate swagger files
swagger: $(GEN_DIR)/$(SWAGGER_NAME).yml $(GEN_DIR)/$(SWAGGER_NAME)-postman.yml

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

