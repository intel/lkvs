# MakeFile function     :: MakeFile for tdx_ebizzy_test_suite

CC                      := gcc

VAR_CFLAGS := $(shell pkg-config --cflags libtracefs 2>/dev/null)
VAR_LDLIBS := $(shell pkg-config --libs libtracefs 2>/dev/null)

CFLAGS                  += -static -Wall -Wextra -g -O2 $(VAR_CFLAGS)
LDFLAGS                 += -lpthread $(VAR_LDLIBS)
INCLUDES                = -I include

#List of source files- Update this on adding a new C file
SOURCES := \
        ebizzy.c \

MAKE_TARGETS            := ebizzy

tdx_guest_test:
	$(CC) $(CFLAGS) $(LDFLAGS) -o ${MAKE_TARGETS} ${INCLUDES} ${SOURCES}

clean:
	rm -rf ${MAKE_TARGETS}
