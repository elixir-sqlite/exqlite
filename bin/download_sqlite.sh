#!/usr/bin/env bash 

set -e

# https://sqlite.org/chronology.html
# https://sqlite.org/download.html
# https://www.sqlite.org/src/timeline?r=version-3.36.0
# VERSION consists of 7 digits, like:3350000 for "3.35.5" or 3360000 for "3.36.0"
#
# Execute with:
#
#   bin/download_sqlite.sh 3460100
#

mkdir -p tmp
pushd tmp

wget https://sqlite.org/2025/sqlite-autoconf-$1.tar.gz

tar xvfz sqlite-autoconf-$1.tar.gz

cp sqlite-autoconf-$1/sqlite3.c ../c_src/
cp sqlite-autoconf-$1/sqlite3.h ../c_src/
cp sqlite-autoconf-$1/sqlite3ext.h ../c_src/

rm -rf sqlite-autoconf-*

popd

echo "UPDATED SQLITE C CODE TO $1!"
