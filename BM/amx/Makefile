# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

SUBDIRS = $(shell ls -d */)

PROXY :=

all:
	@for dir in $(SUBDIRS); do			\
		if [ -f "$$dir/Makefile" ]; then	\
			cd $$dir &&			\
			make || {			\
				cd ..;			\
				continue;		\
			};				\
			cd ..;				\
		fi					\
	done

clean:
	@for dir in $(SUBDIRS); do 				\
		if [ -f "$$dir/Makefile" ]; then		\
			make -C $$dir clean || continue;	\
		fi						\
	done
