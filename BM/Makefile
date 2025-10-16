# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

SUBDIRS = $(shell ls -d */)

PROXY :=

MAKE_LKVS_LOG = /tmp/make_lkvs.log

ifneq ($(https_proxy),)
PROXY := $(https_proxy)
else ifneq ($(HTTPS_PROXY),)
PROXY := $(HTTPS_PROXY)
else ifneq ($(all_proxy),)
PROXY := $(all_proxy)
else ifneq ($(ALL_PROXY),)
PROXY := $(ALL_PROXY)
endif

all:
	@cat /dev/null > ${MAKE_LKVS_LOG};
	@for dir in $(SUBDIRS); do			\
		if [ -f "$$dir/Makefile" ]; then	\
			cd $$dir &&			\
			make || {			\
				echo " - Make subfolder $${dir} failed." >> ${MAKE_LKVS_LOG};	\
				cd ..;			\
				continue;		\
			};				\
			cd ..;				\
		fi					\
	done
	cat $(MAKE_LKVS_LOG)
	@if [ -s ${MAKE_TOOLS_LOG} ]; then \
		echo "Some subfolder failed to build"; \
		exit 2; \
	else \
		echo "All subfolder built successfully"; \
		exit 0; \
	fi

clean:
	@for dir in $(SUBDIRS); do 				\
		if [ -f "$$dir/Makefile" ]; then		\
			make -C $$dir clean || continue;	\
		fi						\
	done
docker_clean:
	docker run -it --rm -v $(PWD):/src --name ubuntu_2204_lkvs ubuntu:22.04 make clean

# Target test and docker_test are for github action mainly.
# It's used to do a compiling validation.
# User should not use this becasue it will be produced the
# module with kernel 5.15 very old one.
test:
	@cp /usr/local/uname /usr/local/sbin/
	$(MAKE) all
	@rm /usr/local/sbin/uname
docker_test:
	docker run -it --rm -v $(PWD):/src --name ubuntu_2204_lkvs ubuntu:22.04 make test

docker_image:
	docker build --build-arg PROXY=$(PROXY) -f ./Dockerfile.build -t ubuntu:22.04 .

docker_image_ddt:
	docker build --build-arg PROXY=$(PROXY) -f ./Dockerfile.build.ddt -t ubuntu:24.04 .

docker_make:
	docker run -it --rm -v $(PWD):/src -v /lib/modules/`uname -r`:/lib/modules/`uname -r` --name ubuntu_2204_lkvs ubuntu:22.04 make

docker_make_ddt:
	docker run -it --rm -v $(PWD):/src -v /lib/modules/`uname -r`:/lib/modules/`uname -r` --name ubuntu_2404_lkvs ubuntu:24.04 make

build:
	@echo "Building $(word 2, $(MAKECMDGOALS))"
	@cd $(word 2, $(MAKECMDGOALS)) && make
	@cd ..

docker-build:
	@echo "Building $* in docker!"
	docker run --rm -v $(PWD):/src --name ubuntu_2204_lkvs ubuntu:22.04 bash -c "make build $(word 2, $(MAKECMDGOALS))"

# Targets build-test and docker-build-test are for test purpose.
# It's used to do a compiling validation.
# User should not use this becasue it will be produced the
# module with kernel 5.15 very old one.
build-test:
	@cp /usr/local/uname /usr/local/sbin/
	@cd $(word 2, $(MAKECMDGOALS)) && make
	@cd ..
	@rm /usr/local/sbin/uname
docker-build-test:
	docker run --rm -v $(PWD):/src --name ubuntu_2204_lkvs ubuntu:22.04 bash -c "make build-test $(word 2, $(MAKECMDGOALS))"

.PHONY: build docker-build
