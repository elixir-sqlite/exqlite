#include <assert.h>
#include <string.h>
#include <stdio.h>

// Elixir workaround for . in module names
#ifdef STATIC_ERLANG_NIF
    #define STATIC_ERLANG_NIF_LIBNAME sqlite3_nif
#endif

#include <erl_nif.h>
#include <sqlite3.h>

#define MAX_ATOM_LENGTH 255
#define MAX_PATHNAME    512

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
make_atom(ErlNifEnv* env, const char* atom_name)
{
    assert(env);
    assert(atom_name);

    ERL_NIF_TERM atom;

    if (enif_make_existing_atom(env, atom_name, &atom, ERL_NIF_LATIN1)) {
        return atom;
    }

    return enif_make_atom(env, atom_name);
}

static ERL_NIF_TERM
make_ok_tuple(ErlNifEnv* env, ERL_NIF_TERM value)
{
    assert(env);
    assert(value);

    return enif_make_tuple2(env, make_atom(env, "ok"), value);
}

static ERL_NIF_TERM
make_error_tuple(ErlNifEnv* env, const char* reason)
{
    assert(env);
    assert(reason);

    return enif_make_tuple2(env, make_atom(env, "error"), make_atom(env, reason));
}

static ERL_NIF_TERM
make_binary(ErlNifEnv* env, const void* bytes, unsigned int size)
{
    ErlNifBinary blob;
    ERL_NIF_TERM term;

    if (!enif_alloc_binary(size, &blob)) {
        return make_atom(env, "out_of_memory");
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

    return enif_make_tuple2(
      env,
      make_atom(env, "error"),
      make_binary(env, msg, len));
}

static ERL_NIF_TERM
exqlite_open(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    int flags;
    int rc             = 0;
    int size           = 0;
    connection_t* conn = NULL;
    sqlite3* db        = NULL;
    ErlNifMutex* mutex = NULL;
    char filename[MAX_PATHNAME];
    ERL_NIF_TERM result;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    size = enif_get_string(env, argv[0], filename, MAX_PATHNAME, ERL_NIF_LATIN1);
    if (size <= 0) {
        return make_error_tuple(env, "invalid_filename");
    }

    if (!enif_get_int(env, argv[1], &flags)) {
        return make_error_tuple(env, "invalid flags");
    }

    rc = sqlite3_open_v2(filename, &db, flags, NULL);
    if (rc != SQLITE_OK) {
        return make_error_tuple(env, "database_open_failed");
    }

    mutex = enif_mutex_create("exqlite:connection");
    if (mutex == NULL) {
        sqlite3_close_v2(db);
        return make_error_tuple(env, "failed_to_create_mutex");
    }

    sqlite3_busy_timeout(db, 2000);

    conn = enif_alloc_resource(connection_type, sizeof(connection_t));
    if (!conn) {
        sqlite3_close_v2(db);
        enif_mutex_destroy(mutex);
        return make_error_tuple(env, "out_of_memory");
    }
    conn->db    = db;
    conn->mutex = mutex;

    result = enif_make_resource(env, conn);
    enif_release_resource(conn);

    return make_ok_tuple(env, result);
}

static ERL_NIF_TERM
exqlite_close(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    connection_t* conn = NULL;
    int rc             = SQLITE_OK;

    if (argc != 1) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, "invalid_connection");
    }

    // DB is already closed, nothing to do here
    if (conn->db == NULL) {
        return make_atom(env, "ok");
    }

    int autocommit = sqlite3_get_autocommit(conn->db);
    if (autocommit == 0) {
        rc = sqlite3_exec(conn->db, "ROLLBACK;", NULL, NULL, NULL);
        if (rc != SQLITE_OK) {
            return make_sqlite3_error_tuple(env, rc, conn->db);
        }
    }

    // close connection in critical section to avoid race-condition
    // cases. Cases such as query timeout and connection pooling
    // attempting to close the connection
    enif_mutex_lock(conn->mutex);

    // note: _v2 may not fully close the connection, hence why we check if
    // any transaction is open above, to make sure other connections aren't blocked.
    // v1 is guaranteed to close or error, but will return error if any
    // unfinalized statements, which we likely have, as we rely on the destructors
    // to later run to clean those up
    rc = sqlite3_close_v2(conn->db);
    if (rc != SQLITE_OK) {
        enif_mutex_unlock(conn->mutex);
        return make_sqlite3_error_tuple(env, rc, conn->db);
    }

    conn->db = NULL;
    enif_mutex_unlock(conn->mutex);

    return make_atom(env, "ok");
}

///
/// @brief Executes an SQL string.
///
static ERL_NIF_TERM
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
        return make_error_tuple(env, "invalid_connection");
    }

    if (!enif_inspect_iolist_as_binary(env, enif_make_list2(env, argv[1], eos), &bin)) {
        return make_error_tuple(env, "sql_not_iolist");
    }

    rc = sqlite3_exec(conn->db, (char*)bin.data, NULL, NULL, NULL);
    if (rc != SQLITE_OK) {
        return make_sqlite3_error_tuple(env, rc, conn->db);
    }

    return make_atom(env, "ok");
}

///
/// @brief Get the number of changes recently done to the database.
///
static ERL_NIF_TERM
exqlite_changes(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    connection_t* conn = NULL;

    if (argc != 1) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (conn->db == NULL) {
        return make_error_tuple(env, "connection_closed");
    }

    int changes = sqlite3_changes(conn->db);
    return make_ok_tuple(env, enif_make_int(env, changes));
}

///
/// @brief Prepares an Sqlite3 statement for execution
///
static ERL_NIF_TERM
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
        return make_error_tuple(env, "invalid_connection");
    }

    if (!enif_inspect_iolist_as_binary(env, enif_make_list2(env, argv[1], eos), &bin)) {
        return make_error_tuple(env, "sql_not_iolist");
    }

    statement = enif_alloc_resource(statement_type, sizeof(statement_t));
    if (!statement) {
        return make_error_tuple(env, "out_of_memory");
    }
    statement->statement = NULL;

    enif_keep_resource(conn);
    statement->conn = conn;

    // ensure connection is not getting closed by parallel thread
    enif_mutex_lock(conn->mutex);
    if (conn->db == NULL) {
        enif_mutex_unlock(conn->mutex);
        enif_release_resource(statement);
        return make_error_tuple(env, "connection_closed");
    }
    rc = sqlite3_prepare_v3(conn->db, (char*)bin.data, bin.size, 0, &statement->statement, NULL);
    enif_mutex_unlock(conn->mutex);

    if (rc != SQLITE_OK) {
        enif_release_resource(statement);
        return make_sqlite3_error_tuple(env, rc, conn->db);
    }

    result = enif_make_resource(env, statement);
    enif_release_resource(statement);

    return make_ok_tuple(env, result);
}

static int
bind(ErlNifEnv* env, const ERL_NIF_TERM arg, sqlite3_stmt* statement, int index)
{
    int the_int;
    ErlNifSInt64 the_long_int;
    double the_double;
    char the_atom[MAX_ATOM_LENGTH + 1];
    ErlNifBinary the_blob;
    int arity;
    const ERL_NIF_TERM* tuple;

    if (enif_get_int(env, arg, &the_int)) {
        return sqlite3_bind_int(statement, index, the_int);
    }

    if (enif_get_int64(env, arg, &the_long_int)) {
        return sqlite3_bind_int64(statement, index, the_long_int);
    }

    if (enif_get_double(env, arg, &the_double)) {
        return sqlite3_bind_double(statement, index, the_double);
    }

    if (enif_get_atom(env, arg, the_atom, sizeof(the_atom), ERL_NIF_LATIN1)) {
        if (0 == strcmp("undefined", the_atom) || 0 == strcmp("nil", the_atom)) {
            return sqlite3_bind_null(statement, index);
        }

        return sqlite3_bind_text(statement, index, the_atom, strlen(the_atom), SQLITE_TRANSIENT);
    }

    if (enif_inspect_iolist_as_binary(env, arg, &the_blob)) {
        return sqlite3_bind_text(statement, index, (char*)the_blob.data, the_blob.size, SQLITE_TRANSIENT);
    }

    if (enif_get_tuple(env, arg, &arity, &tuple)) {
        if (arity != 2) {
            return -1;
        }

        if (enif_get_atom(env, tuple[0], the_atom, sizeof(the_atom), ERL_NIF_LATIN1)) {
            if (0 == strcmp("blob", the_atom)) {
                if (enif_inspect_iolist_as_binary(env, tuple[1], &the_blob)) {
                    return sqlite3_bind_blob(statement, index, the_blob.data, the_blob.size, SQLITE_TRANSIENT);
                }
            }
        }
    }

    return -1;
}

///
/// @brief Binds arguments to the sql statement
///
static ERL_NIF_TERM
exqlite_bind(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    unsigned int parameter_count      = 0;
    unsigned int argument_list_length = 0;
    connection_t* conn                = NULL;
    statement_t* statement            = NULL;
    ERL_NIF_TERM list;
    ERL_NIF_TERM head;
    ERL_NIF_TERM tail;

    if (argc != 3) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (!enif_get_resource(env, argv[1], statement_type, (void**)&statement)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (!enif_get_list_length(env, argv[2], &argument_list_length)) {
        return make_error_tuple(env, "bad_argument_list");
    }

    parameter_count = (unsigned int)sqlite3_bind_parameter_count(statement->statement);
    if (parameter_count != argument_list_length) {
        return make_error_tuple(env, "arguments_wrong_length");
    }

    sqlite3_reset(statement->statement);

    list = argv[2];
    for (unsigned int i = 0; i < argument_list_length; i++) {
        enif_get_list_cell(env, list, &head, &tail);
        int rc = bind(env, head, statement->statement, i + 1);
        if (rc == -1) {
            return enif_make_tuple2(
              env,
              make_atom(env, "error"),
              enif_make_tuple2(
                env,
                make_atom(env, "wrong_type"),
                head));
        }

        if (rc != SQLITE_OK) {
            return make_sqlite3_error_tuple(env, rc, conn->db);
        }

        list = tail;
    }

    return make_atom(env, "ok");
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
            return make_atom(env, "nil");

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
            return make_atom(env, "unsupported");
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
        return make_error_tuple(env, "out_of_memory");
    }

    for (unsigned int i = 0; i < count; i++) {
        columns[i] = make_cell(env, statement, i);
    }

    row = enif_make_list_from_array(env, columns, count);

    enif_free(columns);

    return row;
}

static ERL_NIF_TERM
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
        return make_error_tuple(env, "invalid_connection");
    }

    if (!enif_get_resource(env, argv[1], statement_type, (void**)&statement)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (!statement || !statement->statement) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (!enif_get_int(env, argv[2], &chunk_size)) {
        return make_error_tuple(env, "invalid_chunk_size");
    }

    if (chunk_size < 1) {
        return make_error_tuple(env, "invalid_chunk_size");
    }

    ERL_NIF_TERM rows = enif_make_list_from_array(env, NULL, 0);
    for (int i = 0; i < chunk_size; i++) {
        ERL_NIF_TERM row;

        int rc = sqlite3_step(statement->statement);
        switch (rc) {
            case SQLITE_BUSY:
                sqlite3_reset(statement->statement);
                return make_atom(env, "busy");

            case SQLITE_DONE:
                return enif_make_tuple2(env, make_atom(env, "done"), rows);

            case SQLITE_ROW:
                row  = make_row(env, statement->statement);
                rows = enif_make_list_cell(env, row, rows);
                break;

            default:
                sqlite3_reset(statement->statement);
                return make_sqlite3_error_tuple(env, rc, conn->db);
        }
    }

    return enif_make_tuple2(env, make_atom(env, "rows"), rows);
}

static ERL_NIF_TERM
exqlite_step(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    statement_t* statement = NULL;
    connection_t* conn     = NULL;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (!enif_get_resource(env, argv[1], statement_type, (void**)&statement)) {
        return make_error_tuple(env, "invalid_statement");
    }

    int rc = sqlite3_step(statement->statement);
    switch (rc) {
        case SQLITE_ROW:
            return enif_make_tuple2(
              env,
              make_atom(env, "row"),
              make_row(env, statement->statement));
        case SQLITE_BUSY:
            return make_atom(env, "busy");
        case SQLITE_DONE:
            return make_atom(env, "done");
        default:
            return make_sqlite3_error_tuple(env, rc, conn->db);
    }
}

static ERL_NIF_TERM
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
        return make_error_tuple(env, "invalid_connection");
    }

    if (!enif_get_resource(env, argv[1], statement_type, (void**)&statement)) {
        return make_error_tuple(env, "invalid_statement");
    }

    size = sqlite3_column_count(statement->statement);
    if (size == 0) {
        return make_ok_tuple(env, enif_make_list(env, 0));
    } else if (size < 0) {
        return make_error_tuple(env, "invalid_column_count");
    }

    columns = enif_alloc(sizeof(ERL_NIF_TERM) * size);
    if (!columns) {
        return make_error_tuple(env, "out_of_memory");
    }

    for (int i = 0; i < size; i++) {
        const char* name = sqlite3_column_name(statement->statement, i);
        if (!name) {
            enif_free(columns);
            return make_error_tuple(env, "out_of_memory");
        }

        columns[i] = make_binary(env, name, strlen(name));
    }

    result = enif_make_list_from_array(env, columns, size);
    enif_free(columns);

    return make_ok_tuple(env, result);
}

static ERL_NIF_TERM
exqlite_last_insert_rowid(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    connection_t* conn = NULL;

    if (argc != 1) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, "invalid_connection");
    }

    sqlite3_int64 last_rowid = sqlite3_last_insert_rowid(conn->db);
    return make_ok_tuple(env, enif_make_int64(env, last_rowid));
}

static ERL_NIF_TERM
exqlite_transaction_status(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    connection_t* conn = NULL;

    if (argc != 1) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, "invalid_connection");
    }

    // If the connection times out, DbConnection disconnects the client
    // and then re-opens a new connection. There is a condition where by
    // the connection's database is not set but the calling elixir / erlang
    // pass an incomplete reference.
    if (!conn->db) {
        return make_ok_tuple(env, make_atom(env, "error"));
    }
    int autocommit = sqlite3_get_autocommit(conn->db);
    return make_ok_tuple(
      env,
      autocommit == 0 ? make_atom(env, "transaction") : make_atom(env, "idle"));
}

static ERL_NIF_TERM
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
        return make_error_tuple(env, "invalid_connection");
    }

    if (!enif_inspect_iolist_as_binary(env, enif_make_list2(env, argv[1], eos), &database_name)) {
        return make_error_tuple(env, "database_name_not_iolist");
    }

    buffer = sqlite3_serialize(conn->db, (char*)database_name.data, &buffer_size, 0);
    if (!buffer) {
        return make_error_tuple(env, "serialization_failed");
    }

    serialized = make_binary(env, buffer, buffer_size);
    sqlite3_free(buffer);

    return make_ok_tuple(env, serialized);
}

static ERL_NIF_TERM
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
        return make_error_tuple(env, "invalid_connection");
    }

    if (!enif_inspect_iolist_as_binary(env, enif_make_list2(env, argv[1], eos), &database_name)) {
        return make_error_tuple(env, "database_name_not_iolist");
    }

    if (!enif_inspect_binary(env, argv[2], &serialized)) {
        return enif_make_badarg(env);
    }

    size   = serialized.size;
    buffer = sqlite3_malloc(size);
    if (!buffer) {
        return make_error_tuple(env, "deserialization_failed");
    }

    memcpy(buffer, serialized.data, size);
    rc = sqlite3_deserialize(conn->db, "main", buffer, size, size, flags);
    if (rc != SQLITE_OK) {
        return make_sqlite3_error_tuple(env, rc, conn->db);
    }

    return make_atom(env, "ok");
}

static ERL_NIF_TERM
exqlite_release(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    statement_t* statement = NULL;
    connection_t* conn     = NULL;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (!enif_get_resource(env, argv[1], statement_type, (void**)&statement)) {
        return make_error_tuple(env, "invalid_statement");
    }

    if (statement->statement) {
        sqlite3_finalize(statement->statement);
        statement->statement = NULL;
    }

    return make_atom(env, "ok");
}

static void
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

static void
statement_type_destructor(ErlNifEnv* env, void* arg)
{
    assert(env);
    assert(arg);

    statement_t* statement = (statement_t*)arg;

    if (statement->statement) {
        sqlite3_finalize(statement->statement);
        statement->statement = NULL;
    }

    if (statement->conn) {
        enif_release_resource(statement->conn);
        statement->conn = NULL;
    }
}

static int
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

    connection_type = enif_open_resource_type(
      env,
      "exqlite",
      "connection_type",
      connection_type_destructor,
      ERL_NIF_RT_CREATE,
      NULL);
    if (!connection_type) {
        return -1;
    }

    statement_type = enif_open_resource_type(
      env,
      "exqlite",
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

static ERL_NIF_TERM
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
        return make_error_tuple(env, "invalid_connection");
    }

    if (!enif_get_int(env, argv[1], &enable_load_extension_value)) {
        return make_error_tuple(env, "invalid_enable_load_extension_value");
    }

    rc = sqlite3_enable_load_extension(conn->db, enable_load_extension_value);
    if (rc != SQLITE_OK) {
        return make_sqlite3_error_tuple(env, rc, conn->db);
    }
    return make_atom(env, "ok");
}

//
// Data Change Notifications
//

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
            change_type = make_atom(msg_env, "insert");
            break;
        case SQLITE_DELETE:
            change_type = make_atom(msg_env, "delete");
            break;
        case SQLITE_UPDATE:
            change_type = make_atom(msg_env, "update");
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

static ERL_NIF_TERM
exqlite_set_update_hook(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);
    connection_t* conn = NULL;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (!enif_get_local_pid(env, argv[1], &conn->update_hook_pid)) {
        return make_error_tuple(env, "invalid_pid");
    }

    // Passing the connection as the third argument causes it to be
    // passed as the first argument to update_callback. This allows us
    // to extract the hook pid and reset the hook if the pid is not alive.
    sqlite3_update_hook(conn->db, update_callback, conn);

    return make_atom(env, "ok");
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
    ERL_NIF_TERM msg   = enif_make_tuple3(msg_env, make_atom(msg_env, "log"), enif_make_int(msg_env, iErrCode), error);

    if (!enif_send(NULL, log_hook_pid, msg_env, msg)) {
        enif_mutex_lock(log_hook_mutex);
        sqlite3_config(SQLITE_CONFIG_LOG, NULL, NULL);
        enif_free(log_hook_pid);
        log_hook_pid = NULL;
        enif_mutex_unlock(log_hook_mutex);
    }

    enif_free_env(msg_env);
}

static ERL_NIF_TERM
exqlite_set_log_hook(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    if (argc != 1) {
        return enif_make_badarg(env);
    }

    ErlNifPid* pid = (ErlNifPid*)enif_alloc(sizeof(ErlNifPid));
    if (!enif_get_local_pid(env, argv[0], pid)) {
        enif_free(pid);
        return make_error_tuple(env, "invalid_pid");
    }

    enif_mutex_lock(log_hook_mutex);

    if (log_hook_pid) {
        enif_free(log_hook_pid);
    }

    log_hook_pid = pid;
    sqlite3_config(SQLITE_CONFIG_LOG, log_callback, NULL);

    enif_mutex_unlock(log_hook_mutex);

    return make_atom(env, "ok");
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
  {"bind", 3, exqlite_bind, ERL_NIF_DIRTY_JOB_IO_BOUND},
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
};

ERL_NIF_INIT(Elixir.Exqlite.Sqlite3NIF, nif_funcs, on_load, NULL, NULL, on_unload)
