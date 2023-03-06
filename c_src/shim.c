#define _GNU_SOURCE

#include <stdlib.h>
#include <stdio.h>
#include <pthread.h>
#include "sqlite3.h"
#include <assert.h>

// https://stackoverflow.com/questions/18298280/how-to-declare-a-variable-as-thread-local-portably
#ifndef thread_local
# if __STDC_VERSION__ >= 201112 && !defined __STDC_NO_THREADS__
#  define thread_local _Thread_local
# elif defined _WIN32 && ( \
       defined _MSC_VER || \
       defined __ICL || \
       defined __DMC__ || \
       defined __BORLANDC__ )
#  define thread_local __declspec(thread) 
/* note that ICC (linux) and Clang are covered by __GNUC__ */
# elif defined __GNUC__ || \
       defined __SUNPRO_C || \
       defined __xlC__
#  define thread_local __thread
# else
#  error "Cannot define thread_local"
# endif
#endif


extern void init_mvsqlite(void);
extern void init_mvsqlite_connection(sqlite3 *db);
extern void mvsqlite_autocommit_backoff(sqlite3 *db);

typedef int (*sqlite3_initialize_fn)(void);
typedef int (*sqlite3_open_v2_fn)(
    const char *filename,   /* Database filename (UTF-8) */
    sqlite3 **ppDb,            /* OUT: SQLite db handle */
    int flags,              /* Flags */
    const char *zVfs        /* Name of VFS module to use */
);
typedef int (*sqlite3_step_fn)(sqlite3_stmt *pStmt);

int real_sqlite3_open_v2(
    const char *filename,   /* Database filename (UTF-8) */
    sqlite3 **ppDb,            /* OUT: SQLite db handle */
    int flags,              /* Flags */
    const char *zVfs        /* Name of VFS module to use */
);
int real_sqlite3_step(sqlite3_stmt *pStmt);

static int mvsqlite_enabled = 0;

void mvsqlite_global_init(void) {
    mvsqlite_enabled = 1;
}

static void bootstrap(void) {
    init_mvsqlite();
}

int sqlite3_open_v2(
    const char *filename,   /* Database filename (UTF-8) */
    sqlite3 **ppDb,            /* OUT: SQLite db handle */
    int flags,              /* Flags */
    const char *zVfs        /* Name of VFS module to use */
) {
    int ret;
    bootstrap();
    ret = real_sqlite3_open_v2(filename, ppDb, flags, zVfs);
    if(ret == SQLITE_OK && mvsqlite_enabled) {
        init_mvsqlite_connection(*ppDb);
    }
    return ret;
}

int sqlite3_open(
    const char *filename,   /* Database filename (UTF-8) */
    sqlite3 **ppDb          /* OUT: SQLite db handle */
) {
    return sqlite3_open_v2(filename, ppDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
}

static thread_local int in_sqlite3_step = 0;

int sqlite3_step(sqlite3_stmt *pStmt) {
    int ret;
    int autocommit;
    sqlite3 *db;

    if(in_sqlite3_step) {
        return real_sqlite3_step(pStmt);
    }
    
    in_sqlite3_step = 1;
    db = sqlite3_db_handle(pStmt);

    while (1) {
        autocommit = sqlite3_get_autocommit(db);
        ret = real_sqlite3_step(pStmt);
        if(ret == SQLITE_BUSY && mvsqlite_enabled && autocommit) {
            mvsqlite_autocommit_backoff(db);
        } else {
            in_sqlite3_step = 0;
            return ret;
        }
    }
}
