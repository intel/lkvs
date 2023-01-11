# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

SUBDIRS = $(shell ls -d */)
all:
	for dir in $(SUBDIRS) ; do \
		make -C  $$dir ; \
	done

clean:
	for dir in $(SUBDIRS) ; do \
		make -C  $$dir clean ; \
	done

docker_image:
	docker build --build-arg PROXY=$(https_proxy) -f ./Dockerfile.build -t ubuntu:22.04 .

docker_make:
	docker run -it --rm -v $(PWD):/src --name ubuntu_2204_lkvs ubuntu:22.04 make

docker_clean:
	docker run -it --rm -v $(PWD):/src --name ubuntu_2204_lkvs ubuntu:22.04 make clean
