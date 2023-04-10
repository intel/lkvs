# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

SUBDIRS = $(shell ls -d */)
all:
	@for dir in $(SUBDIRS) ; do			\
		if [ -f "$$dir/Makefile" ]; then	\
			cd $$dir &&			\
			make	&&			\
			cd .. || exit 2;		\
		fi					\
	done

clean:
	for dir in $(SUBDIRS) ; do 			\
		if [ -f "$$dir/Makefile" ]; then	\
			make -C  $$dir clean || exit 2;	\
		fi					\
	done

docker_image:
	docker build --build-arg PROXY=$(https_proxy) -f ./Dockerfile.build -t ubuntu:22.04 .

docker_make:
	docker run -it --rm -v $(PWD):/src --name ubuntu_2204_lkvs ubuntu:22.04 make

docker_clean:
	docker run -it --rm -v $(PWD):/src --name ubuntu_2204_lkvs ubuntu:22.04 make clean


build:
	@echo "Building $(word 2, $(MAKECMDGOALS))"
	@cd $(word 2, $(MAKECMDGOALS)) && make
	@cd ..

docker-build:
	@echo "Building $* in docker!"
	docker run -it --rm -v $(PWD):/src --name ubuntu_2204_lkvs ubuntu:22.04 bash -c "make build $(word 2, $(MAKECMDGOALS))"

.PHONY: build docker-build
