# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

SUBDIRS = $(shell ls -d */)
all:
	for dir in $(SUBDIRS) ; do			\
		if [ -f "$$dir/Makefile" ]; then	\
			make -C $$dir || exit 2;	\
		fi					\
	done

clean:
	for dir in $(SUBDIRS) ; do 			\
		if [ -f "$$dir/Makefile" ]; then	\
			make -C  $$dir clean || exit 2;	\
		fi					\
	done

docker_image:
	docker build -f ./Dockerfile.build -t ubuntu:22.04 .

docker_make:
	docker run -it --rm -v $(PWD):/src --name ubuntu_2204_amx ubuntu:22.04 make

docker_clean:
	docker run -it --rm -v $(PWD):/src --name ubuntu_2204_amx ubuntu:22.04 make clean
