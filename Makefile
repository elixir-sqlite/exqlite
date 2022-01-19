#
# Makefile for building the NIF
#
# Makefile targets:
#
# all    build and install the NIF
# clean  clean build products and intermediates
#
# Variables to override:
#
# MIX_APP_PATH  path to the build directory
#
# CC            The C compiler
# CROSSCOMPILE  crosscompiler prefix, if any
# CFLAGS        compiler flags for compiling all C files
# LDFLAGS       linker flags for linking all binaries
#

SRC = $(wildcard c_src/*.c)
HEADERS = $(wildcard c_src/*.h)

CFLAGS ?= -O2 -Wall
ifneq ($(DEBUG),)
	CFLAGS += -g
endif
CFLAGS += -I"$(ERTS_INCLUDE_DIR)"
CFLAGS += -Ic_src

KERNEL_NAME := $(shell uname -s)

PREFIX = $(MIX_APP_PATH)/priv
BUILD  = $(MIX_APP_PATH)/obj
LIB_NAME = $(PREFIX)/sqlite3_nif.so
ARCHIVE_NAME = $(PREFIX)/sqlite3_nif.a

OBJ = $(SRC:c_src/%.c=$(BUILD)/%.o)

ifneq ($(CROSSCOMPILE),)
	ifeq ($(CROSSCOMPILE), Android)
		CFLAGS += -fPIC -Os -z global
		LDFLAGS += -fPIC -shared
	else
		CFLAGS += -fPIC -fvisibility=hidden
		LDFLAGS += -fPIC -shared
	endif
else
	ifeq ($(KERNEL_NAME), Linux)
		CFLAGS += -fPIC -fvisibility=hidden
		LDFLAGS += -fPIC -shared
	endif
	ifeq ($(KERNEL_NAME), Darwin)
		CFLAGS += -fPIC
		LDFLAGS += -dynamiclib -undefined dynamic_lookup
	endif
	ifeq (MINGW, $(findstring MINGW,$(KERNEL_NAME)))
		CFLAGS += -fPIC
		LDFLAGS += -fPIC -shared
		LIB_NAME = $(PREFIX)/sqlite3_nif.dll
	endif
	ifeq ($(KERNEL_NAME), $(filter $(KERNEL_NAME),OpenBSD FreeBSD NetBSD))
		CFLAGS += -fPIC
		LDFLAGS += -fPIC -shared
	endif
endif

# ########################
# COMPILE TIME DEFINITIONS
# ########################

# For more information about these features being enabled, check out
# --> https://sqlite.org/compile.html
CFLAGS += -DSQLITE_THREADSAFE=1
CFLAGS += -DSQLITE_USE_URI=1
CFLAGS += -DSQLITE_LIKE_DOESNT_MATCH_BLOBS=1
CFLAGS += -DSQLITE_DQS=0
CFLAGS += -DHAVE_USLEEP=1

# TODO: The following features should be completely configurable by the person
#       installing the nif. Just need to have certain environment variables
#       enabled to support them.
CFLAGS += -DALLOW_COVERING_INDEX_SCAN=1
CFLAGS += -DENABLE_FTS3_PARENTHESIS=1
CFLAGS += -DENABLE_LOAD_EXTENSION=1
CFLAGS += -DENABLE_SOUNDEX=1
CFLAGS += -DENABLE_STAT4=1
CFLAGS += -DENABLE_UPDATE_DELETE_LIMIT=1
CFLAGS += -DSQLITE_ENABLE_FTS3=1
CFLAGS += -DSQLITE_ENABLE_FTS4=1
CFLAGS += -DSQLITE_ENABLE_FTS5=1
CFLAGS += -DSQLITE_ENABLE_GEOPOLY=1
CFLAGS += -DSQLITE_ENABLE_JSON1=1
CFLAGS += -DSQLITE_ENABLE_MATH_FUNCTIONS=1
CFLAGS += -DSQLITE_ENABLE_RBU=1
CFLAGS += -DSQLITE_ENABLE_RTREE=1
CFLAGS += -DSQLITE_OMIT_DEPRECATED=1
ifneq ($(STATIC_ERLANG_NIF),)
	CFLAGS += -DSTATIC_ERLANG_NIF=1
endif

# TODO: We should allow the person building to be able to specify this
CFLAGS += -DNDEBUG=1

ifeq ($(STATIC_ERLANG_NIF),)
all: $(PREFIX) $(BUILD) $(LIB_NAME)
else
all: $(PREFIX) $(BUILD) $(ARCHIVE_NAME)
endif

$(BUILD)/%.o: c_src/%.c
	@echo " CC $(notdir $@)"
	$(CC) -c $(CFLAGS) -o $@ $<

$(LIB_NAME): $(OBJ)
	@echo " LD $(notdir $@)"
	$(CC) -o $@ $(LDFLAGS) $^

$(ARCHIVE_NAME): $(OBJ)
	@echo " AR $(notdir $@)"
	$(AR) -rv $@ $^

$(PREFIX) $(BUILD):
	mkdir -p $@

clean:
	$(RM) $(LIB_NAME) $(ARCHIVE_NAME) $(OBJ)

.PHONY: all clean

# Don't echo commands unless the caller exports "V=1"
${V}.SILENT:
