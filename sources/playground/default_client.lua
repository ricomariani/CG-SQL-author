function printf(...) io.write(cql_printf(...)) end

entrypoint(sqlite3.open_memory())
