# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2022 Intel Corporation.

CC       ?= "${CC}" -g -Wall
CFLAGS += -DMAINLINE -I./
BIN	 = cpl branch psb nonroot_test negative_test sort_test
LFLAGS	= -L./ -lipt


all: $(BIN)


cpl:
	$(CC)	-o  $@ $@.c utils.c ${CFLAGS} ${LFLAGS}

branch:
	$(CC)	-o  $@ $@.c utils.c ${CFLAGS} ${LFLAGS}

psb:
	$(CC)	-o  $@ $@.c utils.c ${CFLAGS} ${LFLAGS}

nonroot_test:
	$(CC)	-o  $@ $@.c utils.c ${CFLAGS} ${LFLAGS}

negative_test:
	$(CC)	-o  $@ $@.c utils.c ${CFLAGS} ${LFLAGS}

sort_test:
	$(CC)	-o  $@ $@.c utils.c ${CFLAGS} ${LFLAGS}

clean:
	rm -rf $(BIN) *.o
