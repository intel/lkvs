# MakeFile function     :: MakeFile for tdx_attest_test_suite

CC                      := gcc

VAR_CFLAGS := $(shell pkg-config --cflags libtracefs 2>/dev/null)
VAR_LDLIBS := $(shell pkg-config --libs libtracefs 2>/dev/null)

CFLAGS                  += -static -Wall -Wextra -g -O2 $(VAR_CFLAGS)
LDFLAGS                 += -lpthread $(VAR_LDLIBS)
INCLUDES                = -I include

#List of source files- Update this on adding a new C file
SOURCES := \
        tdx-attest-test.c \

MAKE_TARGETS            := tdx_guest_test

SRC_INC := /usr/include/linux/tdx-guest.h

# Check if TDX_CMD_GET_REPORT0 is defined in tdx-guest.h
VERIFY_REPORT_DEFINED := $(shell grep -c "TDX_CMD_GET_REPORT0" $(SRC_INC))

# Check if TDX_CMD_VERIFY_REPORT is defined in the source code
VERIFY_REPORTMAC_DEFINED := $(shell grep -c "TDX_CMD_VERIFY_REPORT" $(SRC_INC))

# Check if TDX_CMD_EXTEND_RTMR is defined in the source code
VERIFY_RTMR_EXTEND_DEFINED := $(shell grep -c "TDX_CMD_EXTEND_RTMR" $(SRC_INC))

# Check if TDX_CMD_GET_QUOTE is defined in the source code
VERIFY_QUOTE_DEFINED := $(shell grep -c "TDX_CMD_GET_QUOTE" $(SRC_INC))


# Conditional compilation based on whether TDX_CMD_GET_REPORT0 is defined
ifneq ($(VERIFY_REPORT_DEFINED),0)
    # enable compile macro in case of TDX_CMD_GET_REPORT0 is defined
    CFLAGS += -DVERIFY_REPORT
endif

# Conditional compilation based on whether TDX_CMD_VERIFY_REPORT is defined
ifneq ($(VERIFY_REPORTMAC_DEFINED),0)
    # enable compile macro in case of TDX_CMD_VERIFY_REPORT is defined
    CFLAGS += -DVERIFY_REPORTMAC
endif

# Conditional compilation based on whether TDX_CMD_EXTEND_RTMR is defined
ifneq ($(VERIFY_RTMR_EXTEND_DEFINED),0)
    # enable compile macro in case of TDX_CMD_EXTEND_RTMR is defined
    CFLAGS += -DVERIFY_RTMR_EXTEND
endif

# Conditional compilation based on whether TDX_CMD_GET_QUOTE is defined
ifneq ($(VERIFY_QUOTE_DEFINED),0)
    # enable compile macro in case of TDX_CMD_GET_QUOTE is defined
    CFLAGS += -DVERIFY_QUOTE
endif

tdx_guest_test:
	$(CC) $(CFLAGS) $(LDFLAGS) -o ${MAKE_TARGETS} ${INCLUDES} ${SOURCES}

clean:
	rm -rf ${MAKE_TARGETS}
