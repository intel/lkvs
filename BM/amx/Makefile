# SPDX-License-Identifier: GPL-2.0
CFLAG = -O2 -W -Wall -g -fno-strict-aliasing
LIBS = -lpthread
CC = gcc
BIN_AMX = tmul
CFILES_AMX = tmul.c

all: CFLAG += -g -DFP16 -static
all: spr

spr:
	$(CC) $(CFLAG) $(CFILES_AMX) -o $(BIN_AMX) $(LIBS)

clean:
	-rm $(BIN_AMX)

.PHONY: clean

