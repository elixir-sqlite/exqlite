#include <assert.h>
#include <string.h>
#include <stdio.h>

#include <erl_nif.h>
#include <sqlite3.h>

#include "utf8.h"

#define MAX_ATOM_LENGTH 255
#define MAX_PATHNAME    512

static ErlNifResourceType* connection_type = NULL;
static ErlNifResourceType* statement_type  = NULL;

typedef struct connection
{
    sqlite3* db;
} connection_t;

typedef struct statement
{
    sqlite3_stmt* statement;
} statement_t;

static const char*
get_sqlite3_return_code_msg(int rc)
{
    switch (rc) {
        case SQLITE_OK:
            return "ok";
        case SQLITE_ERROR:
            return "sqlite_error";
        case SQLITE_INTERNAL:
            return "internal";
        case SQLITE_PERM:
            return "perm";
        case SQLITE_ABORT:
            return "abort";
        case SQLITE_BUSY:
            return "busy";
        case SQLITE_LOCKED:
            return "locked";
        case SQLITE_NOMEM:
            return "nomem";
        case SQLITE_READONLY:
            return "readonly";
        case SQLITE_INTERRUPT:
            return "interrupt";
        case SQLITE_IOERR:
            return "ioerr";
        case SQLITE_CORRUPT:
            return "corrupt";
        case SQLITE_NOTFOUND:
            return "notfound";
        case SQLITE_FULL:
            return "full";
        case SQLITE_CANTOPEN:
            return "cantopen";
        case SQLITE_PROTOCOL:
            return "protocol";
        case SQLITE_EMPTY:
            return "empty";
        case SQLITE_SCHEMA:
            return "schema";
        case SQLITE_TOOBIG:
            return "toobig";
        case SQLITE_CONSTRAINT:
            return "constraint";
        case SQLITE_MISMATCH:
            return "mismatch";
        case SQLITE_MISUSE:
            return "misuse";
        case SQLITE_NOLFS:
            return "nolfs";
        case SQLITE_AUTH:
            return "auth";
        case SQLITE_FORMAT:
            return "format";
        case SQLITE_RANGE:
            return "range";
        case SQLITE_NOTADB:
            return "notadb";
        case SQLITE_NOTICE:
            return "notice";
        case SQLITE_WARNING:
            return "warning";
        case SQLITE_ROW:
            return "row";
        case SQLITE_DONE:
            return "done";
        case SQLITE_ERROR_MISSING_COLLSEQ:
            return "error_missing_collseq";
        case SQLITE_ERROR_RETRY:
            return "error_retry";
        case SQLITE_ERROR_SNAPSHOT:
            return "error_snapshot";
        case SQLITE_IOERR_READ:
            return "ioerr_read";
        case SQLITE_IOERR_SHORT_READ:
            return "ioerr_short_read";
        case SQLITE_IOERR_WRITE:
            return "ioerr_write";
        case SQLITE_IOERR_FSYNC:
            return "ioerr_fsync";
        case SQLITE_IOERR_DIR_FSYNC:
            return "ioerr_dir_fsync";
        case SQLITE_IOERR_TRUNCATE:
            return "ioerr_truncate";
        case SQLITE_IOERR_FSTAT:
            return "ioerr_fstat";
        case SQLITE_IOERR_UNLOCK:
            return "ioerr_unlock";
        case SQLITE_IOERR_RDLOCK:
            return "ioerr_rdlock";
        case SQLITE_IOERR_DELETE:
            return "ioerr_delete";
        case SQLITE_IOERR_BLOCKED:
            return "ioerr_blocked";
        case SQLITE_IOERR_NOMEM:
            return "ioerr_nomem";
        case SQLITE_IOERR_ACCESS:
            return "ioerr_access";
        case SQLITE_IOERR_CHECKRESERVEDLOCK:
            return "ioerr_checkreservedlock";
        case SQLITE_IOERR_LOCK:
            return "ioerr_lock";
        case SQLITE_IOERR_CLOSE:
            return "ioerr_close";
        case SQLITE_IOERR_DIR_CLOSE:
            return "ioerr_dir_close";
        case SQLITE_IOERR_SHMOPEN:
            return "ioerr_shmopen";
        case SQLITE_IOERR_SHMSIZE:
            return "ioerr_shmsize";
        case SQLITE_IOERR_SHMLOCK:
            return "ioerr_shmlock";
        case SQLITE_IOERR_SHMMAP:
            return "ioerr_shmmap";
        case SQLITE_IOERR_SEEK:
            return "ioerr_seek";
        case SQLITE_IOERR_DELETE_NOENT:
            return "ioerr_delete_noent";
        case SQLITE_IOERR_MMAP:
            return "ioerr_mmap";
        case SQLITE_IOERR_GETTEMPPATH:
            return "ioerr_gettemppath";
        case SQLITE_IOERR_CONVPATH:
            return "ioerr_convpath";
        case SQLITE_IOERR_VNODE:
            return "ioerr_vnode";
        case SQLITE_IOERR_AUTH:
            return "ioerr_auth";
        case SQLITE_IOERR_BEGIN_ATOMIC:
            return "ioerr_begin_atomic";
        case SQLITE_IOERR_COMMIT_ATOMIC:
            return "ioerr_commit_atomic";
        case SQLITE_IOERR_ROLLBACK_ATOMIC:
            return "ioerr_rollback_atomic";
        case SQLITE_IOERR_DATA:
            return "ioerr_data";
        case SQLITE_IOERR_CORRUPTFS:
            return "ioerr_corruptfs";
        case SQLITE_LOCKED_SHAREDCACHE:
            return "locked_sharedcache";
        case SQLITE_LOCKED_VTAB:
            return "locked_vtab";
        case SQLITE_BUSY_RECOVERY:
            return "busy_recovery";
        case SQLITE_BUSY_SNAPSHOT:
            return "busy_snapshot";
        case SQLITE_BUSY_TIMEOUT:
            return "busy_timeout";
        case SQLITE_CANTOPEN_NOTEMPDIR:
            return "cantopen_notempdir";
        case SQLITE_CANTOPEN_ISDIR:
            return "cantopen_isdir";
        case SQLITE_CANTOPEN_FULLPATH:
            return "cantopen_fullpath";
        case SQLITE_CANTOPEN_CONVPATH:
            return "cantopen_convpath";
        case SQLITE_CANTOPEN_DIRTYWAL:
            return "cantopen_dirtywal";
        case SQLITE_CANTOPEN_SYMLINK:
            return "cantopen_symlink";
        case SQLITE_CORRUPT_VTAB:
            return "corrupt_vtab";
        case SQLITE_CORRUPT_SEQUENCE:
            return "corrupt_sequence";
        case SQLITE_CORRUPT_INDEX:
            return "corrupt_index";
        case SQLITE_READONLY_RECOVERY:
            return "readonly_recovery";
        case SQLITE_READONLY_CANTLOCK:
            return "readonly_cantlock";
        case SQLITE_READONLY_ROLLBACK:
            return "readonly_rollback";
        case SQLITE_READONLY_DBMOVED:
            return "readonly_dbmoved";
        case SQLITE_READONLY_CANTINIT:
            return "readonly_cantinit";
        case SQLITE_READONLY_DIRECTORY:
            return "readonly_directory";
        case SQLITE_ABORT_ROLLBACK:
            return "abort_rollback";
        case SQLITE_CONSTRAINT_CHECK:
            return "constraint_check";
        case SQLITE_CONSTRAINT_COMMITHOOK:
            return "constraint_commithook";
        case SQLITE_CONSTRAINT_FOREIGNKEY:
            return "constraint_foreignkey";
        case SQLITE_CONSTRAINT_FUNCTION:
            return "constraint_function";
        case SQLITE_CONSTRAINT_NOTNULL:
            return "constraint_notnull";
        case SQLITE_CONSTRAINT_PRIMARYKEY:
            return "constraint_primarykey";
        case SQLITE_CONSTRAINT_TRIGGER:
            return "constraint_trigger";
        case SQLITE_CONSTRAINT_UNIQUE:
            return "constraint_unique";
        case SQLITE_CONSTRAINT_VTAB:
            return "constraint_vtab";
        case SQLITE_CONSTRAINT_ROWID:
            return "constraint_rowid";
        case SQLITE_CONSTRAINT_PINNED:
            return "constraint_pinned";
        case SQLITE_NOTICE_RECOVER_WAL:
            return "notice_recover_wal";
        case SQLITE_NOTICE_RECOVER_ROLLBACK:
            return "notice_recover_rollback";
        case SQLITE_WARNING_AUTOINDEX:
            return "warning_autoindex";
        default:
            return "unknown";
    }
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
make_sqlite3_error_tuple(ErlNifEnv* env, int rc, sqlite3* db)
{
    const char* error_code_msg = get_sqlite3_return_code_msg(rc);
    const char* msg            = get_sqlite3_error_msg(rc, db);

    return enif_make_tuple2(
      env,
      make_atom(env, "error"),
      enif_make_tuple2(
        env,
        make_atom(env, error_code_msg),
        enif_make_string(env, msg, ERL_NIF_LATIN1)));
}

static ERL_NIF_TERM
exqlite_open(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    int rc             = 0;
    int size           = 0;
    connection_t* conn = NULL;
    char filename[MAX_PATHNAME];
    ERL_NIF_TERM result;

    if (argc != 1) {
        return enif_make_badarg(env);
    }

    size = enif_get_string(env, argv[0], filename, MAX_PATHNAME, ERL_NIF_LATIN1);
    if (size <= 0) {
        return make_error_tuple(env, "invalid_filename");
    }

    conn = enif_alloc_resource(connection_type, sizeof(connection_t));
    if (!conn) {
        return make_error_tuple(env, "out_of_memory");
    }

    rc = sqlite3_open(filename, &conn->db);
    if (rc != SQLITE_OK) {
        enif_release_resource(conn);
        return make_error_tuple(env, "database_open_failed");
    }

    sqlite3_busy_timeout(conn->db, 2000);

    result = enif_make_resource(env, conn);
    enif_release_resource(conn);

    return make_ok_tuple(env, result);
}

static ERL_NIF_TERM
exqlite_close(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    connection_t* conn = NULL;

    if (argc != 1) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, "invalid_connection");
    }

    sqlite3_close_v2(conn->db);
    conn->db = NULL;

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

    enif_inspect_iolist_as_binary(env,
                                  enif_make_list2(env, argv[1], eos),
                                  &bin);

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

    rc = sqlite3_prepare_v3(conn->db, (char*)bin.data, bin.size, 0, &statement->statement, NULL);
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
        if (0 == utf8ncmp("undefined", the_atom, 9)) {
            return sqlite3_bind_null(statement, index);
        }

        return sqlite3_bind_text(statement, index, the_atom, utf8len(the_atom), SQLITE_TRANSIENT);
    }

    if (enif_inspect_iolist_as_binary(env, arg, &the_blob)) {
        return sqlite3_bind_text(statement, index, (char*)the_blob.data, the_blob.size, SQLITE_TRANSIENT);
    }

    if (enif_get_tuple(env, arg, &arity, &tuple)) {
        if (arity != 2) {
            return -1;
        }

        if (enif_get_atom(env, tuple[0], the_atom, sizeof(the_atom), ERL_NIF_LATIN1)) {
            if (0 == utf8ncmp("blob", the_atom, 4)) {
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
///
/// @brief Finalize aka delete a prepared statement.
///
static ERL_NIF_TERM
exqlite_finalize(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    assert(env);

    connection_t* conn     = NULL;
    statement_t* statement = NULL;
    int rc;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_get_resource(env, argv[0], connection_type, (void**)&conn)) {
        return make_error_tuple(env, "invalid_connection");
    }

    if (!enif_get_resource(env, argv[1], statement_type, (void**)&statement)) {
        return make_error_tuple(env, "invalid_statement");
    }

    rc = sqlite3_finalize(statement->statement);
    if (rc != SQLITE_OK) {
        return make_sqlite3_error_tuple(env, rc, conn->db);
    }

    return make_atom(env, "ok");
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
make_cell(ErlNifEnv* env, sqlite3_stmt* statement, unsigned int i)
{
    size_t len = 0;

    switch (sqlite3_column_type(statement, i)) {
        case SQLITE_INTEGER:
            return enif_make_int64(env, sqlite3_column_int64(statement, i));

        case SQLITE_FLOAT:
            return enif_make_double(env, sqlite3_column_double(statement, i));

        case SQLITE_NULL:
            return make_atom(env, "undefined");

        case SQLITE_BLOB:
            len = sqlite3_column_bytes(statement, i);
            return enif_make_tuple2(
              env,
              make_atom(env, "blob"),
              make_binary(env, sqlite3_column_blob(statement, i), len));

        case SQLITE_TEXT:
            len = sqlite3_column_bytes(statement, i);
            return enif_make_tuple2(
              env,
              make_atom(env, "text"),
              make_binary(env, sqlite3_column_text(statement, i), len));

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

    return enif_make_tuple2(env, make_atom(env, "row"), row);
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
            return make_row(env, statement->statement);
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
        const char* type = sqlite3_column_decltype(statement->statement, i);
        if (!name) {
            enif_free(columns);
            return make_error_tuple(env, "out_of_memory");
        }

        if (type == NULL) {
            type = "nil";
        }

        columns[i] = enif_make_tuple2(env, make_atom(env, name), make_atom(env, type));
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
}

static void
statement_type_destructor(ErlNifEnv* env, void* arg)
{
    assert(env);

    statement_t* statement = (statement_t*)arg;
    sqlite3_finalize(statement->statement);
    statement->statement = NULL;
}

static int
on_load(ErlNifEnv* env, void** priv, ERL_NIF_TERM info)
{
    assert(env);

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

    return 0;
}

//
// Most of our nif functions are going to be IO bounded
//

static ErlNifFunc nif_funcs[] = {
  {"open", 1, exqlite_open, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"close", 1, exqlite_close, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"execute", 2, exqlite_execute, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"changes", 1, exqlite_changes, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"prepare", 2, exqlite_prepare, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"bind", 3, exqlite_bind, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"finalize", 2, exqlite_finalize, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"step", 2, exqlite_step, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"columns", 2, exqlite_columns, ERL_NIF_DIRTY_JOB_IO_BOUND},
  {"last_insert_rowid", 1, exqlite_last_insert_rowid, ERL_NIF_DIRTY_JOB_IO_BOUND},
};

ERL_NIF_INIT(Elixir.Exqlite.Sqlite3NIF, nif_funcs, on_load, NULL, NULL, NULL)
