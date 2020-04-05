# -*- mode: Makefile -*-
#

SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

# To override
#override MYVAR := someval
#include....

include $(SELF_DIR)util.mk

$(call check_defined, STACK_NAME, stack name)
$(call check_defined, PACKAGE_OUTPUT_BUCKET, lambda output bucket)
$(call check_defined, GEN_DIR, generated output base directory)

SAM_BUILD_OUTPUT_TEMPLATE = $(GEN_DIR)/.packaged.yaml

# Prefix (orders becomes orders-api.yml). Assumes file naming logic in stack.py.
SWAGGER_BASE_NAME=$(STACK_NAME)-api
SWAGGER_FILE=$(GEN_DIR)/$(SWAGGER_BASE_NAME).yaml

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
	sdk \
	swagger \
	swagger-postman

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

swagger-postman:
	@mkdir -p $(GEN_DIR)
	@$(SELF_DIR)stack.py swagger -d $(GEN_DIR) -s $(STACK_NAME) -e postman

swagger:
	@mkdir -p $(GEN_DIR)
	@$(SELF_DIR)stack.py swagger -d $(GEN_DIR) -s $(STACK_NAME) -e none

sdk:
	@mkdir -p $(GEN_DIR)
	@$(SELF_DIR)stack.py sdk -d $(GEN_DIR) -s $(STACK_NAME)


