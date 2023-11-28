# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

TOOLSDIRS = $(shell ls -d */)
MAKE_TOOLS_LOG = /tmp/make_tools.log

all:
	@cat /dev/null > ${MAKE_TOOLS_LOG};
	@for tooldir in $(TOOLSDIRS); do		\
		if [ -f "$$tooldir/Makefile" ]; then	\
			cd $$tooldir &&			\
			make || {			\
				cd ..;			\
				echo " - Make tools $${tooldir} failed." >> ${MAKE_TOOLS_LOG};	\
				continue;		\
			};				\
			cd ..;				\
		fi					\
	done
	@cat ${MAKE_TOOLS_LOG}
ifeq ($(shell cat $(MAKE_TOOLS_LOG)),)
	@exit 0
else
	@exit 1
endif

clean:
	@for tooldir in $(TOOLSDIRS); do 			\
		if [ -f "$$tooldir/Makefile" ]; then		\
			make -C $$tooldir clean || continue;	\
		fi						\
	done
