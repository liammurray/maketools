# -*- mode: Makefile -*-
#

SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

include $(SELF_DIR)util.mk

$(call check_defined, STACK_NAME, stack name)
$(call check_defined, PACKAGE_OUTPUT_BUCKET, lambda output bucket)
$(call check_defined, GEN_DIR, generated output base directory)

# Intermediate template produced by sam build command.
# We skip this and package from the SAM template (because we do labmda dist build ourselves).
# SAM_PACKAGE_TEMPLATE = .aws-sam/build/template.yaml

SAM_TEMPLATE = ./template.yml

# Final deployable CFN template (with code uri references pointing to S3 locations)
SAM_DEPLOY_TEMPLATE?=$(GEN_DIR)/.packaged.yaml


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
	lint \
	clean \
	build \
	api \
	validate \
	package \
	deploy \
	errors \
	generated-clean \
	output \
	output-table \
	sdk \
	swagger \
	swagger-postman \
	version-dev

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

lint:
	@set -e; for dir in $(subdirs); do \
		cd $$dir; \
		npm run lint; \
	 done

clean: clean-projects clean-layer
	@rm -rf .aws-sam
	@rm -f $$SAM_DEPLOY_TEMPLATE


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

ifeq "$(USE_CDK)" "true"

deploy:
	@cd ./stack && cdk deploy

destroy:
	@cd ./stack && cdk destroy

package:
	@echo "No package step for CDK (skipping)"

else

$(SAM_DEPLOY_TEMPLATE): build
	sam package \
		--template-file $(SAM_TEMPLATE) \
		--output-template-file $(SAM_DEPLOY_TEMPLATE) \
	  --s3-bucket $(PACKAGE_OUTPUT_BUCKET)

package: $(SAM_DEPLOY_TEMPLATE)


deploy: $(SAM_DEPLOY_TEMPLATE)
	sam deploy \
		--template-file $(SAM_DEPLOY_TEMPLATE) \
		--stack-name $(STACK_NAME) \
		--capabilities CAPABILITY_NAMED_IAM

# changeset: $(SAM_DEPLOY_TEMPLATE)
# 	@aws cloudformation deploy \
# 		--no-execute-changeset \
# 		--template-file $(SAM_DEPLOY_TEMPLATE) \
# 		--stack-name $(STACK_NAME) \
# 		--capabilities CAPABILITY_NAMED_IAM

destroy:
	aws cloudformation delete-stack \
			--stack-name $(STACK_NAME)

endif



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
	@$(SELF_DIR)/py3/stack.py swagger -d $(GEN_DIR) -e postman $(STACK_NAME)

swagger:
	@mkdir -p $(GEN_DIR)
	@$(SELF_DIR)/py3/stack.py swagger -d $(GEN_DIR) -e none $(STACK_NAME)

sdk:
	@mkdir -p $(GEN_DIR)
	@$(SELF_DIR)/py3/stack.py sdk -d $(GEN_DIR) $(STACK_NAME)

version-dev:
	$(eval ID=$(shell $(MAKETOOLS)/getStackOutputVal.sh $(STACK_NAME) ApiId))
	aws apigateway get-stages --rest-api-id $(ID) --query 'item[?stageName==`dev`]'

