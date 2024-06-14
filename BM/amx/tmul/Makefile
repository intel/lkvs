# SPDX-License-Identifier: GPL-2.0
CFLAG = -O2 -W -Wall -g -fno-strict-aliasing
LIBS = -lpthread
CC = gcc
BIN_AMX = tmul
CFILES_AMX = tmul.c

all:
	$(CC) $(CFLAG) $(CFILES_AMX) -o $(BIN_AMX) $(LIBS)

fp16: CFLAG += -g -DFP16
fp16: all

clean:
	-rm $(BIN_AMX)

.PHONY: clean

