#pragma once

#include "sqlite3.h"

extern void init_mvsqlite(void);
extern void init_mvsqlite_connection(sqlite3 *db);
extern void mvsqlite_autocommit_backoff(sqlite3 *db);

typedef int (*sqlite3_initialize_fn)(void);
typedef int (*sqlite3_open_v2_fn)(
    const char *filename,
    sqlite3 **ppDb,
    int flags,
    const char *zVfs
);
typedef int (*sqlite3_step_fn)(sqlite3_stmt *pStmt);

int real_sqlite3_open_v2(
    const char *filename,
    sqlite3 **ppDb,
    int flags,
    const char *zVfs
);
int real_sqlite3_step(sqlite3_stmt *pStmt);

void mvsqlite_global_init(void);

static void bootstrap(void);

int sqlite3_open_v2(
    const char *filename,
    sqlite3 **ppDb,
    int flags,
    const char *zVfs
);

int sqlite3_open(
    const char *filename,
    sqlite3 **ppDb
);

int sqlite3_step(sqlite3_stmt *pStmt);
