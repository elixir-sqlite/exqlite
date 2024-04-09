CFLAGS += -O2 -fPIC

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
	LDFLAGS += -Wl,-z,noexecstack
endif
ifeq ($(UNAME_S),Darwin)
    LDFLAGS += -framework Security
endif

build-preload: preload.o shim.o
	$(CC) $(CFLAGS) -shared $(LDFLAGS) \
		-o libmvsqlite_preload.so \
		preload.o shim.o \
		-L../target/release -lmvsqlite -lsqlite3 -lpthread -ldl -lm

build-lib: shim.o
	ar rcs libmvsqlite.a shim.o

build-patched-sqlite3:
	$(CC) $(CFLAGS) -shared -o libsqlite3.so $(LDFLAGS) \
		-DSQLITE_ENABLE_FTS3 \
		-DSQLITE_ENABLE_FTS4 \
		-DSQLITE_ENABLE_FTS5 \
		-DSQLITE_ENABLE_RTREE \
		-DSQLITE_ENABLE_DBSTAT_VTAB \
		-DSQLITE_ENABLE_MATH_FUNCTIONS \
		-DSQLITE_ENABLE_COLUMN_METADATA \
		-DMV_STATIC_PATCH \
		./sqlite3.c ./preload.c ./shim.c \
			-L../target/release -lmvsqlite -lpthread -ldl -lm

clean:
	rm -f libmvsqlite_preload.so preload.o shim.o

.PHONY: clean
