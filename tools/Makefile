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
