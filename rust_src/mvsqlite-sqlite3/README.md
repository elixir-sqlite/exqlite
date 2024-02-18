# mvsqlite for Windows

```bat
REM for windows
REM scoop install llvm-mingw@20220323
```

```bat
cmd
scoop uninstall llvm-mingw
scoop install llvm openssl-mingw
cargo build --release -p mvsqlite
cd mvsqlite-sqlite3
set CC="%userprofile%/scoop/apps/mingw/current/bin/x86_64-w64-mingw32-gcc.exe"
mingw32-make.exe build-patched-sqlite3
```

## Check fdb status

```bash
'C:\Program Files\foundationdb\bin\fdbcli.exe'
status
# Migrate the database from in-memory to ssd
configure perpetual_storage_wiggle=1 storage_migration_type=gradual
configure single ssd
# Check the status
status
```

## Start sqlite client

```cmd
set RUST_LOG=info
set MVSQLITE_DATA_PLANE=http://localhost:7000
sqlite3.exe mvsqlite
.tables
```

## Starting mvstore with foundationdb on Linux

```bash
# on Linux
wget https://github.com/apple/foundationdb/releases/download/7.1.15/foundationdb-clients_7.1.15-1_amd64.deb
sudo dpkg -i foundationdb-clients_7.1.15-1_amd64.deb
wget https://github.com/apple/foundationdb/releases/download/7.1.15/foundationdb-server_7.1.15-1_amd64.deb
sudo dpkg -i foundationdb-server_7.1.15-1_amd64.deb
cargo build --release -p mvstore
RUST_LOG=info ./mvstore \
  --data-plane 127.0.0.1:7000 \
  --admin-api 127.0.0.1:7001 \
  --metadata-prefix mvstore \
  --raw-data-prefix m
```

## Starting mvstore with foundationdb on Windows

```bash
cmd
REM install https://github.com/apple/foundationdb/releases/download/7.1.25/foundationdb-7.1.25-x64.msi
REM Copy fdb_c_types.h
cargo build --release -p mvstore
$env:RUST_LOG="info"
./mvstore.exe --data-plane 127.0.0.1:7000 --admin-api 127.0.0.1:7001 --metadata-prefix mvstore --raw-data-prefix m --cluster "C:/ProgramData/foundationdb/fdb.cluster"
```

## Copy fdb_c_types.h to `C:/Program Files/foundationdb/include/foundationdb/fdb_c_types.h`

```C
/*
 * fdb_c_types.h
 *
 * This source file is part of the FoundationDB open source project
 *
 * Copyright 2013-2022 Apple Inc. and the FoundationDB project authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef FDB_C_TYPES_H
#define FDB_C_TYPES_H
#pragma once

#ifndef DLLEXPORT
#define DLLEXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Pointers to these opaque types represent objects in the FDB API */
typedef struct FDB_future FDBFuture;
typedef struct FDB_result FDBResult;
typedef struct FDB_cluster FDBCluster;
typedef struct FDB_database FDBDatabase;
typedef struct FDB_tenant FDBTenant;
typedef struct FDB_transaction FDBTransaction;

typedef int fdb_error_t;
typedef int fdb_bool_t;

#ifdef __cplusplus
}
#endif
#endif
```

## Create a mvsqlite database

```bat
scoop install curl
curl http://localhost:7001/api/create_namespace --include --data {\"key\":\"mvsqlite\"}
```

## Debugging library loading

```powershell
scoop install Dependencies 
```
