#!/usr/bin/env bash 

# https://sqlite.org/chronology.html
# https://sqlite.org/download.html
# https://www.sqlite.org/src/timeline?r=version-3.36.0
# VERSION consists of 7 digits, like:3350000 for "3.35.5" or 3360000 for "3.36.0"

VERSION=3360000 # 3.36.0

mkdir -p tmp
pushd tmp

wget https://sqlite.org/2021/sqlite-autoconf-$VERSION.tar.gz

tar xvfz sqlite-autoconf-$VERSION.tar.gz
cd sqlite-autoconf-$VERSION

cp sqlite3.c ../../c_src/
cp sqlite3.h ../../c_src/
cp sqlite3ext.h ../../c_src/

rm -rf tmp/*

echo "UPDATED SQLITE C CODE TO $VERSION!"
