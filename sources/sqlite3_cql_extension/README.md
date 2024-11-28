# SQLite3 CQL Extension

## Requirements

### Local SQLite3

- Code source must be available to compile the extension (sqlite3ext.h).
- The compiled SQLite3 binary must allow loading extensions
- The version of the binary must match the version of the code source

```bash
git clone https://github.com/sqlite/sqlite.git && cd sqlite
./configure && make sqlite3-all.c
gcc -g -O0 -DSQLITE_ENABLE_LOAD_EXTENSION -o sqlite3 sqlite3-all.c shell.c
```
## How to use it

```bash
# Export the path of the sqlite sqlite3 source code
export SQLITE_PATH=../../../sqlite

# Build the extension
./make.sh

# Run the tests
./test.sh

# Use the extension
## Linux
$SQLITE_PATH/sqlite3 ":memory:" -cmd ".load out/cqlextension.so" "SELECT hello_world();"
## MacOS
$SQLITE_PATH/sqlite3 ":memory:" -cmd ".load out/cqlextension.dylib" "SELECT hello_world();"
## Windows
$SQLITE_PATH/sqlite3 ":memory:" -cmd ".load out/cqlextension.dll" "SELECT hello_world();"
```
