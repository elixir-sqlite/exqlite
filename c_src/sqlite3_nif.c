#include <assert.h>
#include <string.h>
#include <stdio.h>

// Elixir workaround for . in module names
#ifdef STATIC_ERLANG_NIF
    #define STATIC_ERLANG_NIF_LIBNAME sqlite3_nif
#endif

#include <erl_nif.h>
#include <sqlite3.h>

static ERL_NIF_TERM am_ok;
static ERL_NIF_TERM am_error;
static ERL_NIF_TERM am_badarg;
static ERL_NIF_TERM am_nil;
static ERL_NIF_TERM am_out_of_memory;
static ERL_NIF_TERM am_done;
static ERL_NIF_TERM am_row;
static ERL_NIF_TERM am_rows;
static ERL_NIF_TERM am_invalid_filename;
static ERL_NIF_TERM am_invalid_flags;
static ERL_NIF_TERM am_database_open_failed;
static ERL_NIF_TERM am_failed_to_create_mutex;
static ERL_NIF_TERM am_invalid_connection;
static ERL_NIF_TERM am_sql_not_iolist;
static ERL_NIF_TERM am_connection_closed;
static ERL_NIF_TERM am_invalid_statement;
static ERL_NIF_TERM am_invalid_chunk_size;
static ERL_NIF_TERM am_busy;
static ERL_NIF_TERM am_invalid_column_count;
static ERL_NIF_TERM am_transaction;
static ERL_NIF_TERM am_idle;
static ERL_NIF_TERM am_database_name_not_iolist;
static ERL_NIF_TERM am_serialization_failed;
static ERL_NIF_TERM am_deserialization_failed;
static ERL_NIF_TERM am_invalid_enable_load_extension_value;
static ERL_NIF_TERM am_insert;
static ERL_NIF_TERM am_delete;
static ERL_NIF_TERM am_update;
static ERL_NIF_TERM am_invalid_pid;
static ERL_NIF_TERM am_log;

static ErlNifResourceType* connection_type       = NULL;
static ErlNifResourceType* statement_type        = NULL;
static sqlite3_mem_methods default_alloc_methods = {0};

ErlNifPid* log_hook_pid     = NULL;
ErlNifMutex* log_hook_mutex = NULL;

typedef struct connection
{
    sqlite3* db;
    ErlNifMutex* mutex;
    ErlNifPid update_hook_pid;
} connection_t;

typedef struct statement
{
    connection_t* conn;
    sqlite3_stmt* statement;
} statement_t;

static void*
exqlite_malloc(int bytes)
{
    assert(bytes > 0);

    size_t* p = enif_alloc(bytes + sizeof(size_t));
    if (p) {
        p[0] = bytes;
        p++;
    }

    return p;
}

static void
exqlite_free(void* prior)
{
    if (!prior) {
        return;
    }

    size_t* p = prior;

    // Shift the pointer back to free the proper block of data
    p--;

    enif_free(p);
}

static void*
exqlite_realloc(void* prior, int bytes)
{
    assert(prior);
    assert(bytes > 0);

    size_t* p = prior;
    p--;

    p = enif_realloc(p, bytes + sizeof(size_t));
    if (p) {
        p[0] = bytes;
        p++;
    }

    return p;
}

static int
exqlite_mem_size(void* prior)
{
    if (!prior) {
        return 0;
    }

    size_t* p = prior;
    p--;

    return p[0];
}

static int
exqlite_mem_round_up(int bytes)
{
    return (bytes + 7) & ~7;
}

static int
exqlite_mem_init(void* ptr)
{
    return SQLITE_OK;
}

static void
exqlite_mem_shutdown(void* ptr)
{
}

static const char*
get_sqlite3_error_msg(int rc, sqlite3* db)
{
    if (rc == SQLITE_MISUSE) {
        return "Sqlite3 was invoked incorrectly.";
    }

    const char* message = sqlite3_errmsg(db);
    if (!message) {
        return "No error message available.";
    }
    return message;
}

static ERL_NIF_TERM
make_ok_tuple(ErlNifEnv* env, ERL_NIF_TERM value)
{
    assert(env);
    assert(value);

    return enif_make_tuple2(env, am_ok, value);
}

static ERL_NIF_TERM
make_error_tuple(ErlNifEnv* env, ERL_NIF_TERM reason)
{
    assert(env);
    assert(reason);

    return enif_make_tuple2(env, am_error, reason);
}

static ERL_NIF_TERM
make_binary(ErlNifEnv* env, const void* bytes, unsigned int size)
{
    ErlNifBinary blob;
    ERL_NIF_TERM term;

    if (!enif_alloc_binary(size, &blob)) {
        return am_out_of_memory;
    }

    memcpy(blob.data, bytes, size);
    term = enif_make_binary(env, &blob);
    enif_release_binary(&blob);

    return term;
}

static ERL_NIF_TERM
make_sqlite3_error_tuple(ErlNifEnv* env, int rc, sqlite3* db)
{
    const char* msg = get_sqlite3_error_msg(rc, db);
    size_t len      = strlen(msg);
    return make_error_tuple(env, make_binary(env, msg, len));
}

static ERL_NIF_TERM
raise_badarg(ErlNifEnv* env, ERL_NIF_TERM term)
{
    ERL_NIF_TERM badarg = enif_make_tuple2(env, am_badarg, term);
    return enif_raise_exception(env, badarg);
}

static ERL_NIF_TERM
make_cell(ErlNifEnv* env, sqlite3_stmt* statement, unsigned int i)
{
    switch (sqlite3_column_type(statement, i)) {
        case SQLITE_INTEGER:
            return enif_make_int64(env, sqlite3_column_int64(statement, i));

        case SQLITE_FLOAT:
            return enif_make_double(env, sqlite3_column_double(statement, i));

        case SQLITE_NULL:
            return am_nil;

        case SQLITE_BLOB:
            return make_binary(
              env,
              sqlite3_column_blob(statement, i),
              sqlite3_column_bytes(statement, i));

        case SQLITE_TEXT:
            return make_binary(
              env,
              sqlite3_column_text(statement, i),
              sqlite3_column_bytes(statement, i));

        default:
            return am_nil;
    }
}

static ERL_NIF_TERM
make_row(ErlNifEnv* env, sqlite3_stmt* statement)
{
    assert(env);
    assert(statement);

    ERL_NIF_TERM* columns = NULL;
    ERL_NIF_TERM row;
    unsigned int count = sqlite3_column_count(statement);

    columns = enif_alloc(sizeof(ERL_NIF_TERM) * count);
    if (!columns) {
        return make_error_tuple(env, am_out_of_memory);
    }

    for (unsigned int i = 0; i < count; i++) {
        columns[i] = make_cell(env, statement, i);
    }

    row = enif_make_list_from_array(env, columns, count);

    enif_free(columns);

    return row;
}

static inline void
connection_acquire_lock(connection_t* conn)
{
    assert(conn);
    enif_mutex_lock(conn->mutex);
}

static inline void
connection_release_lock(connection_t* conn)
{
    assert(conn);
    enif_mutex_unlock(conn->mutex);
}

static inline void
statement_acquire_lock(statement_t* statement)
{
    assert(statement);
    connection_acquire_lock(statement->conn);
}

static inline void
statement_release_lock(statement_t* statement)
{
    assert(statement);
    connection_release_lock(statement->conn);
}

///
/// Opens a new SQLite database
///
ERL_NIF_TERM
exqlite_open(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    int flags;
    int rc             = 0;
    int size           = 0;
    connection_t* conn = NULL;
    sqlite3* db        = NULL;
    ErlNifMutex* mutex = NULL;
    ERL_NIF_TERM result;
    ErlNifBinary bin;

    ERL_NIF_TERM eos = enif_make_int(env, 0);

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_inspect_iolist_as_binary(env, enif_make_list2(env, argv[0], eos), &bin)) {
        return make_error_tuple(env, am_invalid_filename);
    }

    if (!enif_get_int(env, argv[1], &flags)) {
        return make_error_tuple(env, am_invalid_flags);
    }

    rc = sqlite3_open_v2((char*)bin.data, &db, flags, NULL);
    if (rc != SQLITE_OK) {
        return make_error_tuple(env, am_database_open_failed);
    }

    mutex = enif_mutex_create("exqlite:connection");
    if (mutex == NULL) {
        sqlite3_close_v2(db);
        return make_error_tuple(env, am_failed_to_create_mutex);
    }

    sqlite3_busy_timeout(db, 2000);

    conn = enif_alloc_resource(connection_type, sizeof(connection_t));
    if (!conn) {
        sqlite3_close_v2(db);
        enif_mutex_destroy(mutex);
        return make_error_tuple(env, am_out_of_memory);
    }
    conn->db    = db;
    conn->mutex = mutex;

    result = enif_make_resource(env, conn);
    enif_release_resource(conn);

    return make_ok_tuple(env, result);
}

///
/// Closes an SQLite database
///
ERL_NIF_TERM
exqlite_close(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    connection_t* conn = NULL;
    int rc             = SQLITE_OK;

    if (argc != 1) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    // DB is already closed, nothing to do here
    if (conn->db == NULL) {
        return am_ok;
    }

    // close connection in critical section to avoid race-condition
    // cases. Cases such as query timeout and connection pooling
    // attempting to close the connection
    connection_acquire_lock(conn);

    int autocommit = sqlite3_get_autocommit(conn->db);
    if (autocommit == 0) {
        rc = sqlite3_exec(conn->db, "ROLLBACK;", NULL, NULL, NULL);
        if (rc != SQLITE_OK) {
            connection_release_lock(conn);
            return make_sqlite3_error_tuple(env, rc, conn->db);
        }
    }

    // note: _v2 may not fully close the connection, hence why we check if
    // any transaction is open above, to make sure other connections aren't blocked.
    // v1 is guaranteed to close or error, but will return error if any
    // unfinalized statements, which we likely have, as we rely on the destructors
    // to later run to clean those up
    rc = sqlite3_close_v2(conn->db);
    if (rc != SQLITE_OK) {
        connection_release_lock(conn);
        return make_sqlite3_error_tuple(env, rc, conn->db);
    }

    conn->db = NULL;
    connection_release_lock(conn);

    return am_ok;
}

///
/// Executes an SQL string.
///
ERL_NIF_TERM
exqlite_execute(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    ErlNifBinary bin;
    connection_t* conn = NULL;
    ERL_NIF_TERM eos   = enif_make_int(env, 0);
    int rc             = SQLITE_OK;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    if (!enif_inspect_iolist_as_binary(env, enif_make_list2(env, argv[1], eos), &bin)) {
        return make_error_tuple(env, am_sql_not_iolist);
    }

    connection_acquire_lock(conn);

    rc = sqlite3_exec(conn->db, (char*)bin.data, NULL, NULL, NULL);
    if (rc != SQLITE_OK) {
        connection_release_lock(conn);
        return make_sqlite3_error_tuple(env, rc, conn->db);
    }

    connection_release_lock(conn);

    return am_ok;
}

///
/// Get the number of changes recently done to the database.
///
ERL_NIF_TERM
exqlite_changes(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    connection_t* conn = NULL;

    if (argc != 1) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    if (conn->db == NULL) {
        return make_error_tuple(env, am_connection_closed);
    }

    connection_acquire_lock(conn);
    int changes = sqlite3_changes(conn->db);
    connection_release_lock(conn);
    return make_ok_tuple(env, enif_make_int(env, changes));
}

///
/// Prepares an Sqlite3 statement for execution
///
ERL_NIF_TERM
exqlite_prepare(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    ErlNifBinary bin;
    connection_t* conn     = NULL;
    statement_t* statement = NULL;
    ERL_NIF_TERM result;
    int rc;
    ERL_NIF_TERM eos = enif_make_int(env, 0);

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    if (!enif_inspect_iolist_as_binary(env, enif_make_list2(env, argv[1], eos), &bin)) {
        return make_error_tuple(env, am_sql_not_iolist);
    }

    statement = enif_alloc_resource(statement_type, sizeof(statement_t));
    if (!statement) {
        return make_error_tuple(env, am_out_of_memory);
    }
    statement->statement = NULL;

    enif_keep_resource(conn);
    statement->conn = conn;

    // ensure connection is not getting closed by parallel thread
    connection_acquire_lock(conn);
    if (conn->db == NULL) {
        connection_release_lock(conn);
        enif_release_resource(statement);
        return make_error_tuple(env, am_connection_closed);
    }

    rc = sqlite3_prepare_v3(conn->db, (char*)bin.data, bin.size, 0, &statement->statement, NULL);

    if (rc != SQLITE_OK) {
        result = make_sqlite3_error_tuple(env, rc, conn->db);
        connection_release_lock(conn);
        enif_release_resource(statement);
        return result;
    }

    connection_release_lock(conn);

    result = enif_make_resource(env, statement);
    enif_release_resource(statement);

    return make_ok_tuple(env, result);
}

///
/// Reset the prepared statement
///
ERL_NIF_TERM
exqlite_reset(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    statement_t* statement;
    if (!enif_get_resource(env, argv[0], statement_type, (void**)&statement)) {
        return raise_badarg(env, argv[0]);
    }

    statement_acquire_lock(statement);
    sqlite3_reset(statement->statement);
    statement_release_lock(statement);
    return am_ok;
}

///
/// Get the bind parameter count
///
ERL_NIF_TERM
exqlite_bind_parameter_count(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    statement_t* statement;
    if (!enif_get_resource(env, argv[0], statement_type, (void**)&statement)) {
        return raise_badarg(env, argv[0]);
    }

    statement_acquire_lock(statement);
    int bind_parameter_count = sqlite3_bind_parameter_count(statement->statement);
    statement_release_lock(statement);
    return enif_make_int(env, bind_parameter_count);
}

///
/// Binds a text parameter
///
ERL_NIF_TERM
exqlite_bind_text(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    statement_t* statement;
    if (!enif_get_resource(env, argv[0], statement_type, (void**)&statement)) {
        return raise_badarg(env, argv[0]);
    }

    unsigned int idx;
    if (!enif_get_uint(env, argv[1], &idx)) {
        return raise_badarg(env, argv[1]);
    }

    ErlNifBinary text;
    if (!enif_inspect_binary(env, argv[2], &text)) {
        return raise_badarg(env, argv[2]);
    }

    statement_acquire_lock(statement);
    int rc = sqlite3_bind_text(statement->statement, idx, (char*)text.data, text.size, SQLITE_TRANSIENT);
    statement_release_lock(statement);
    return enif_make_int(env, rc);
}

///
/// Binds a blob parameter
///
ERL_NIF_TERM
exqlite_bind_blob(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    statement_t* statement;
    if (!enif_get_resource(env, argv[0], statement_type, (void**)&statement)) {
        return raise_badarg(env, argv[0]);
    }

    unsigned int idx;
    if (!enif_get_uint(env, argv[1], &idx)) {
        return raise_badarg(env, argv[1]);
    }

    ErlNifBinary blob;
    if (!enif_inspect_binary(env, argv[2], &blob)) {
        return raise_badarg(env, argv[2]);
    }

    statement_acquire_lock(statement);
    int rc = sqlite3_bind_blob(statement->statement, idx, (char*)blob.data, blob.size, SQLITE_TRANSIENT);
    statement_release_lock(statement);
    return enif_make_int(env, rc);
}

///
/// Binds an integer parameter
///
ERL_NIF_TERM
exqlite_bind_integer(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    statement_t* statement;
    if (!enif_get_resource(env, argv[0], statement_type, (void**)&statement)) {
        return raise_badarg(env, argv[0]);
    }

    unsigned int idx;
    if (!enif_get_uint(env, argv[1], &idx)) {
        return raise_badarg(env, argv[1]);
    }

    ErlNifSInt64 i;
    if (!enif_get_int64(env, argv[2], &i)) {
        return raise_badarg(env, argv[2]);
    }

    statement_acquire_lock(statement);
    int rc = sqlite3_bind_int64(statement->statement, idx, i);
    statement_release_lock(statement);
    return enif_make_int(env, rc);
}

///
/// Binds a float parameter
///
ERL_NIF_TERM
exqlite_bind_float(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    statement_t* statement;
    if (!enif_get_resource(env, argv[0], statement_type, (void**)&statement)) {
        return raise_badarg(env, argv[0]);
    }

    unsigned int idx;
    if (!enif_get_uint(env, argv[1], &idx)) {
        return raise_badarg(env, argv[1]);
    }

    double f;
    if (!enif_get_double(env, argv[2], &f)) {
        return raise_badarg(env, argv[2]);
    }

    statement_acquire_lock(statement);
    int rc = sqlite3_bind_double(statement->statement, idx, f);
    statement_release_lock(statement);
    return enif_make_int(env, rc);
}

///
/// Binds a null parameter
///
ERL_NIF_TERM
exqlite_bind_null(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    statement_t* statement;
    if (!enif_get_resource(env, argv[0], statement_type, (void**)&statement)) {
        return raise_badarg(env, argv[0]);
    }

    unsigned int idx;
    if (!enif_get_uint(env, argv[1], &idx)) {
        return raise_badarg(env, argv[1]);
    }

    statement_acquire_lock(statement);
    int rc = sqlite3_bind_null(statement->statement, idx);
    statement_release_lock(statement);
    return enif_make_int(env, rc);
}

///
/// Steps the sqlite prepared statement multiple times.
///
/// This is to reduce the back and forth between the BEAM and sqlite in
/// fetching data. Without using this, throughput can suffer.
///
ERL_NIF_TERM
exqlite_multi_step(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    statement_t* statement = NULL;
    connection_t* conn     = NULL;
    int chunk_size;

    if (argc != 3) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    if (!enif_get_resource(env, argv[1], statement_type, (void**)&statement)) {
        return make_error_tuple(env, am_invalid_statement);
    }

    if (!statement || !statement->statement) {
        return make_error_tuple(env, am_invalid_statement);
    }

    if (!enif_get_int(env, argv[2], &chunk_size)) {
        return make_error_tuple(env, am_invalid_chunk_size);
    }

    if (chunk_size < 1) {
        return make_error_tuple(env, am_invalid_chunk_size);
    }

    connection_acquire_lock(conn);

    ERL_NIF_TERM rows = enif_make_list_from_array(env, NULL, 0);
    for (int i = 0; i < chunk_size; i++) {
        ERL_NIF_TERM row;

        int rc = sqlite3_step(statement->statement);
        switch (rc) {
            case SQLITE_BUSY:
                sqlite3_reset(statement->statement);
                connection_release_lock(conn);
                return am_busy;

            case SQLITE_DONE:
                sqlite3_reset(statement->statement);
                connection_release_lock(conn);
                return enif_make_tuple2(env, am_done, rows);

            case SQLITE_ROW:
                row  = make_row(env, statement->statement);
                rows = enif_make_list_cell(env, row, rows);
                break;

            default:
                sqlite3_reset(statement->statement);
                connection_release_lock(conn);
                return make_sqlite3_error_tuple(env, rc, conn->db);
        }
    }

    connection_release_lock(conn);

    return enif_make_tuple2(env, am_rows, rows);
}

///
/// Invokes one step on the SQLite prepared statement's results. If multiple
/// steps are being taken, throughput may suffer, but this does allow for
/// better interleaved calls to a NIF and letting the VM do more bookkeeping
///
ERL_NIF_TERM
exqlite_step(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    ERL_NIF_TERM result;
    statement_t* statement = NULL;
    connection_t* conn     = NULL;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    if (!enif_get_resource(env, argv[1], statement_type, (void**)&statement)) {
        return make_error_tuple(env, am_invalid_statement);
    }

    connection_acquire_lock(conn);

    int rc = sqlite3_step(statement->statement);
    switch (rc) {
        case SQLITE_ROW:
            result = enif_make_tuple2(env, am_row, make_row(env, statement->statement));
            connection_release_lock(conn);
            return result;
        case SQLITE_BUSY:
            sqlite3_reset(statement->statement);
            connection_release_lock(conn);
            return am_busy;
        case SQLITE_DONE:
            sqlite3_reset(statement->statement);
            connection_release_lock(conn);
            return am_done;
        default:
            sqlite3_reset(statement->statement);
            result = make_sqlite3_error_tuple(env, rc, conn->db);
            connection_release_lock(conn);
            return result;
    }
}

///
/// Get the columns requested in a prepared statement
///
ERL_NIF_TERM
exqlite_columns(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    int size               = 0;
    statement_t* statement = NULL;
    connection_t* conn     = NULL;
    ERL_NIF_TERM* columns;
    ERL_NIF_TERM result;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    if (!enif_get_resource(env, argv[1], statement_type, (void**)&statement)) {
        return make_error_tuple(env, am_invalid_statement);
    }

    statement_acquire_lock(statement);
    size = sqlite3_column_count(statement->statement);

    if (size == 0) {
        statement_release_lock(statement);
        return make_ok_tuple(env, enif_make_list(env, 0));
    } else if (size < 0) {
        statement_release_lock(statement);
        return make_error_tuple(env, am_invalid_column_count);
    }

    columns = enif_alloc(sizeof(ERL_NIF_TERM) * size);
    if (!columns) {
        statement_release_lock(statement);
        return make_error_tuple(env, am_out_of_memory);
    }

    for (int i = 0; i < size; i++) {
        const char* name = sqlite3_column_name(statement->statement, i);
        if (!name) {
            enif_free(columns);
            statement_release_lock(statement);
            return make_error_tuple(env, am_out_of_memory);
        }

        columns[i] = make_binary(env, name, strlen(name));
    }

    statement_release_lock(statement);

    result = enif_make_list_from_array(env, columns, size);
    enif_free(columns);

    return make_ok_tuple(env, result);
}

///
/// Get the last inserted row id.
///
ERL_NIF_TERM
exqlite_last_insert_rowid(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    connection_t* conn = NULL;

    if (argc != 1) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    connection_acquire_lock(conn);
    sqlite3_int64 last_rowid = sqlite3_last_insert_rowid(conn->db);
    connection_release_lock(conn);
    return make_ok_tuple(env, enif_make_int64(env, last_rowid));
}

///
/// Get the current transaction status
///
ERL_NIF_TERM
exqlite_transaction_status(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    connection_t* conn = NULL;

    if (argc != 1) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    // If the connection times out, DbConnection disconnects the client
    // and then re-opens a new connection. There is a condition where by
    // the connection's database is not set but the calling elixir / erlang
    // pass an incomplete reference.
    if (!conn->db) {
        return make_ok_tuple(env, am_error);
    }

    connection_acquire_lock(conn);
    int autocommit = sqlite3_get_autocommit(conn->db);
    connection_release_lock(conn);

    return make_ok_tuple(
      env,
      autocommit == 0 ? am_transaction : am_idle);
}

ERL_NIF_TERM
exqlite_serialize(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    connection_t* conn = NULL;
    ErlNifBinary database_name;
    ERL_NIF_TERM eos          = enif_make_int(env, 0);
    unsigned char* buffer     = NULL;
    sqlite3_int64 buffer_size = 0;
    ERL_NIF_TERM serialized;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    if (!enif_inspect_iolist_as_binary(env, enif_make_list2(env, argv[1], eos), &database_name)) {
        return make_error_tuple(env, am_database_name_not_iolist);
    }

    connection_acquire_lock(conn);

    buffer = sqlite3_serialize(conn->db, (char*)database_name.data, &buffer_size, 0);
    if (!buffer) {
        connection_release_lock(conn);
        return make_error_tuple(env, am_serialization_failed);
    }

    serialized = make_binary(env, buffer, buffer_size);
    sqlite3_free(buffer);

    connection_release_lock(conn);

    return make_ok_tuple(env, serialized);
}

ERL_NIF_TERM
exqlite_deserialize(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    connection_t* conn    = NULL;
    unsigned char* buffer = NULL;
    ErlNifBinary database_name;
    ERL_NIF_TERM eos = enif_make_int(env, 0);
    ErlNifBinary serialized;
    int size  = 0;
    int rc    = 0;
    int flags = SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_RESIZEABLE;

    if (argc != 3) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    if (!enif_inspect_iolist_as_binary(env, enif_make_list2(env, argv[1], eos), &database_name)) {
        return make_error_tuple(env, am_database_name_not_iolist);
    }

    if (!enif_inspect_binary(env, argv[2], &serialized)) {
        return enif_make_badarg(env);
    }

    connection_acquire_lock(conn);

    size   = serialized.size;
    buffer = sqlite3_malloc(size);
    if (!buffer) {
        return make_error_tuple(env, am_deserialization_failed);
    }

    memcpy(buffer, serialized.data, size);
    rc = sqlite3_deserialize(conn->db, "main", buffer, size, size, flags);
    if (rc != SQLITE_OK) {
        connection_release_lock(conn);
        return make_sqlite3_error_tuple(env, rc, conn->db);
    }

    connection_release_lock(conn);
    return am_ok;
}

///
/// Releases a prepared statement's consumed memory and allows the system to
/// reclaim it.
///
ERL_NIF_TERM
exqlite_release(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    statement_t* statement = NULL;
    connection_t* conn     = NULL;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    if (!enif_get_resource(env, argv[1], statement_type, (void**)&statement)) {
        return make_error_tuple(env, am_invalid_statement);
    }

    statement_acquire_lock(statement);

    if (statement->statement) {
        sqlite3_finalize(statement->statement);
        statement->statement = NULL;
    }

    statement_release_lock(statement);

    return am_ok;
}

void
connection_type_destructor(ErlNifEnv* env, void* arg)
{
    assert(env);
    assert(arg);

    connection_t* conn = (connection_t*)arg;

    if (conn->db) {
        sqlite3_close_v2(conn->db);
        conn->db = NULL;
    }

    if (conn->mutex) {
        enif_mutex_destroy(conn->mutex);
        conn->mutex = NULL;
    }
}

void
statement_type_destructor(ErlNifEnv* env, void* arg)
{
    assert(env);
    assert(arg);

    statement_t* statement = (statement_t*)arg;
    statement_acquire_lock(statement);

    if (statement->statement) {
        sqlite3_finalize(statement->statement);
        statement->statement = NULL;
    }

    statement_release_lock(statement);
    enif_release_resource(statement->conn);
    statement->conn = NULL;
}

int
on_load(ErlNifEnv* env, void** priv, ERL_NIF_TERM info)
{
    assert(env);

    static const sqlite3_mem_methods methods = {
      exqlite_malloc,
      exqlite_free,
      exqlite_realloc,
      exqlite_mem_size,
      exqlite_mem_round_up,
      exqlite_mem_init,
      exqlite_mem_shutdown,
      0};

    sqlite3_config(SQLITE_CONFIG_GETMALLOC, &default_alloc_methods);
    sqlite3_config(SQLITE_CONFIG_MALLOC, &methods);

    am_ok                                  = enif_make_atom(env, "ok");
    am_error                               = enif_make_atom(env, "error");
    am_badarg                              = enif_make_atom(env, "badarg");
    am_nil                                 = enif_make_atom(env, "nil");
    am_out_of_memory                       = enif_make_atom(env, "out_of_memory");
    am_done                                = enif_make_atom(env, "done");
    am_row                                 = enif_make_atom(env, "row");
    am_rows                                = enif_make_atom(env, "rows");
    am_invalid_filename                    = enif_make_atom(env, "invalid_filename");
    am_invalid_flags                       = enif_make_atom(env, "invalid_flags");
    am_database_open_failed                = enif_make_atom(env, "database_open_failed");
    am_failed_to_create_mutex              = enif_make_atom(env, "failed_to_create_mutex");
    am_invalid_connection                  = enif_make_atom(env, "invalid_connection");
    am_sql_not_iolist                      = enif_make_atom(env, "sql_not_iolist");
    am_connection_closed                   = enif_make_atom(env, "connection_closed");
    am_invalid_statement                   = enif_make_atom(env, "invalid_statement");
    am_invalid_chunk_size                  = enif_make_atom(env, "invalid_chunk_size");
    am_busy                                = enif_make_atom(env, "busy");
    am_invalid_column_count                = enif_make_atom(env, "invalid_column_count");
    am_transaction                         = enif_make_atom(env, "transaction");
    am_idle                                = enif_make_atom(env, "idle");
    am_database_name_not_iolist            = enif_make_atom(env, "database_name_not_iolist");
    am_serialization_failed                = enif_make_atom(env, "serialization_failed");
    am_deserialization_failed              = enif_make_atom(env, "deserialization_failed");
    am_invalid_enable_load_extension_value = enif_make_atom(env, "invalid_enable_load_extension_value");
    am_insert                              = enif_make_atom(env, "insert");
    am_delete                              = enif_make_atom(env, "delete");
    am_update                              = enif_make_atom(env, "update");
    am_invalid_pid                         = enif_make_atom(env, "invalid_pid");
    am_log                                 = enif_make_atom(env, "log");

    connection_type = enif_open_resource_type(
      env,
      NULL,
      "connection_type",
      connection_type_destructor,
      ERL_NIF_RT_CREATE,
      NULL);
    if (!connection_type) {
        return -1;
    }

    statement_type = enif_open_resource_type(
      env,
      NULL,
      "statement_type",
      statement_type_destructor,
      ERL_NIF_RT_CREATE,
      NULL);
    if (!statement_type) {
        return -1;
    }

    log_hook_mutex = enif_mutex_create("exqlite:log_hook");
    if (!log_hook_mutex) {
        return -1;
    }

    return 0;
}

static void
on_unload(ErlNifEnv* caller_env, void* priv_data)
{
    assert(caller_env);

    sqlite3_config(SQLITE_CONFIG_MALLOC, &default_alloc_methods);
    enif_mutex_destroy(log_hook_mutex);
}

//
// Enable extension loading
//

ERL_NIF_TERM
exqlite_enable_load_extension(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);
    connection_t* conn = NULL;
    int rc             = SQLITE_OK;
    int enable_load_extension_value;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    if (!enif_get_int(env, argv[1], &enable_load_extension_value)) {
        return make_error_tuple(env, am_invalid_enable_load_extension_value);
    }

    rc = sqlite3_enable_load_extension(conn->db, enable_load_extension_value);
    if (rc != SQLITE_OK) {
        return make_sqlite3_error_tuple(env, rc, conn->db);
    }
    return am_ok;
}

///
/// Data Change Notifications
///
void
update_callback(void* arg, int sqlite_operation_type, char const* sqlite_database, char const* sqlite_table, sqlite3_int64 sqlite_rowid)
{
    connection_t* conn = (connection_t*)arg;

    if (conn == NULL) {
        return;
    }

    ErlNifEnv* msg_env = enif_alloc_env();
    ERL_NIF_TERM change_type;

    switch (sqlite_operation_type) {
        case SQLITE_INSERT:
            change_type = am_insert;
            break;
        case SQLITE_DELETE:
            change_type = am_delete;
            break;
        case SQLITE_UPDATE:
            change_type = am_update;
            break;
        default:
            return;
    }
    ERL_NIF_TERM rowid    = enif_make_int64(msg_env, sqlite_rowid);
    ERL_NIF_TERM database = make_binary(msg_env, sqlite_database, strlen(sqlite_database));
    ERL_NIF_TERM table    = make_binary(msg_env, sqlite_table, strlen(sqlite_table));
    ERL_NIF_TERM msg      = enif_make_tuple4(msg_env, change_type, database, table, rowid);

    if (!enif_send(NULL, &conn->update_hook_pid, msg_env, msg)) {
        sqlite3_update_hook(conn->db, NULL, NULL);
    }

    enif_free_env(msg_env);
}

ERL_NIF_TERM
exqlite_set_update_hook(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);
    connection_t* conn = NULL;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return am_invalid_connection;
    }

    if (!enif_get_local_pid(env, argv[1], &conn->update_hook_pid)) {
        return am_invalid_pid;
    }

    connection_acquire_lock(conn);

    // Passing the connection as the third argument causes it to be
    // passed as the first argument to update_callback. This allows us
    // to extract the hook pid and reset the hook if the pid is not alive.
    sqlite3_update_hook(conn->db, update_callback, conn);

    connection_release_lock(conn);

    return am_ok;
}

//
// Log Notifications
//

void
log_callback(void* arg, int iErrCode, const char* zMsg)
{
    if (log_hook_pid == NULL) {
        return;
    }

    ErlNifEnv* msg_env = enif_alloc_env();
    ERL_NIF_TERM error = make_binary(msg_env, zMsg, strlen(zMsg));
    ERL_NIF_TERM msg   = enif_make_tuple3(msg_env, am_log, enif_make_int(msg_env, iErrCode), error);

    if (!enif_send(NULL, log_hook_pid, msg_env, msg)) {
        enif_mutex_lock(log_hook_mutex);
        sqlite3_config(SQLITE_CONFIG_LOG, NULL, NULL);
        enif_free(log_hook_pid);
        log_hook_pid = NULL;
        enif_mutex_unlock(log_hook_mutex);
    }

    enif_free_env(msg_env);
}

ERL_NIF_TERM
exqlite_set_log_hook(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 1) {
        return enif_make_badarg(env);
    }

    ErlNifPid* pid = (ErlNifPid*)enif_alloc(sizeof(ErlNifPid));
    if (!enif_get_local_pid(env, argv[0], pid)) {
        enif_free(pid);
        return make_error_tuple(env, am_invalid_pid);
    }

    enif_mutex_lock(log_hook_mutex);

    if (log_hook_pid) {
        enif_free(log_hook_pid);
    }

    log_hook_pid = pid;
    sqlite3_config(SQLITE_CONFIG_LOG, log_callback, NULL);

    enif_mutex_unlock(log_hook_mutex);

    return am_ok;
}

///
/// Interrupt a long-running query.
///
ERL_NIF_TERM
exqlite_interrupt(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    connection_t* conn = NULL;

    if (argc != 1) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, am_invalid_connection);
    }

    // DB is already closed, nothing to do here
    if (conn->db == NULL) {
        return am_ok;
    }

    // connection_acquire_lock(conn);
    sqlite3_interrupt(conn->db);
    // connection_release_lock(conn);

    return am_ok;
}

ERL_NIF_TERM
exqlite_errmsg(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    connection_t* conn;
    statement_t* statement;
    const char* msg;

    if (enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        connection_acquire_lock(conn);
        msg = sqlite3_errmsg(conn->db);
        connection_release_lock(conn);
    } else if (enif_get_resource(env, argv[0], statement_type, (void**)&statement)) {
        statement_acquire_lock(statement);
        msg = sqlite3_errmsg(sqlite3_db_handle(statement->statement));
        statement_release_lock(statement);
    } else {
        return raise_badarg(env, argv[0]);
    }

    if (!msg) {
        return am_nil;
    }

    return make_binary(env, msg, strlen(msg));
}

ERL_NIF_TERM
exqlite_errstr(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    int rc;
    if (!enif_get_int(env, argv[0], &rc)) {
        return raise_badarg(env, argv[0]);
    }

    const char* msg = sqlite3_errstr(rc);
    return make_binary(env, msg, strlen(msg));
}

//
// Most of our nif functions are going to be IO bounded
//

static ErlNifFunc nif_funcs[] = {
  {"open", 2, exqlite_open, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"close", 1, exqlite_close, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"execute", 2, exqlite_execute, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"changes", 1, exqlite_changes, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"prepare", 2, exqlite_prepare, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"reset", 1, exqlite_reset, ERL_NIF_DIRTY_JOB_CPU_BOUND},
  {"bind_parameter_count", 1, exqlite_bind_parameter_count},
  {"bind_text", 3, exqlite_bind_text},
  {"bind_blob", 3, exqlite_bind_blob},
  {"bind_integer", 3, exqlite_bind_integer},
  {"bind_float", 3, exqlite_bind_float},
  {"bind_null", 2, exqlite_bind_null},
  {"step", 2, exqlite_step, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"multi_step", 3, exqlite_multi_step, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"columns", 2, exqlite_columns, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"last_insert_rowid", 1, exqlite_last_insert_rowid, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"transaction_status", 1, exqlite_transaction_status, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"serialize", 2, exqlite_serialize, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"deserialize", 3, exqlite_deserialize, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"release", 2, exqlite_release, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"enable_load_extension", 2, exqlite_enable_load_extension, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"set_update_hook", 2, exqlite_set_update_hook, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"set_log_hook", 1, exqlite_set_log_hook, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"interrupt", 1, exqlite_interrupt, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"errmsg", 1, exqlite_errmsg},
  {"errstr", 1, exqlite_errstr},
};

ERL_NIF_INIT(Elixir.Exqlite.Sqlite3NIF, nif_funcs, on_load, NULL, NULL, on_unload)
