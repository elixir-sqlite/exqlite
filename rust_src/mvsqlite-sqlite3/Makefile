CFLAGS += -O2 -fPIC

build-patched-sqlite3: mvsqlite
	$(CC) -O2 -o sqlite3 \
		-DSQLITE_ENABLE_FTS3 \
		-DSQLITE_ENABLE_FTS4 \
		-DSQLITE_ENABLE_FTS5 \
		-DSQLITE_ENABLE_RTREE \
		-DSQLITE_ENABLE_DBSTAT_VTAB \
		-DSQLITE_ENABLE_MATH_FUNCTIONS \
		-DSQLITE_ENABLE_COLUMN_METADATA \
		./sqlite3.c ./shim.c  ./shell.c \
		$(LIBS)

LIBS = ""

ifeq ($(shell uname -s), Darwin)
	LIBS = -L../target/release -lmvsqlite -lpthread -lm -framework Security
else
	LIBS = -L../target/release -lmvsqlite -lpthread -lm -lws2_32 -lbcrypt -luserenv -lntdll
endif

clean:
	rm -f libmvsqlite_preload.so preload.o shim.o sqlite3.exe sqlite3

.PHONY: clean

mvsqlite:
	cargo build --release -p mvsqlite