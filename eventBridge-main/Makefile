SHELL := /usr/bin/env bash
TF  ?= terraform
TFL ?= tflint

TF_DIRS := modules/eventbridge_org examples/lambda_from_ssm examples/sqs_with_dlq

.PHONY: init fmt fmt-check lint validate check all

init:
	@for d in $(TF_DIRS); do         		echo "==> $$d: terraform init -backend=false";         		( cd $$d && $(TF) init -backend=false -upgrade );         	done

fmt:
	@echo "==> terraform fmt (write)"
	@$(TF) fmt -recursive

fmt-check:
	@echo "==> terraform fmt (check only)"
	@$(TF) fmt -recursive -check

lint:
	@echo "==> tflint init + lint"
	@$(TFL) --init
	@for d in $(TF_DIRS); do         		echo "==> tflint $$d";         		$(TFL) --chdir $$d;         	done

validate:
	@for d in $(TF_DIRS); do         		echo "==> $$d: terraform validate";         		( cd $$d && $(TF) validate );         	done

check: fmt-check lint validate
	@echo "==> All local checks passed"

all: init fmt check
