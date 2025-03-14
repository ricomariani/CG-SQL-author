---
title: "Appendix 10: A Working Example"
weight: 10
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

This is a working example that shows all of the basic DML statements and the call patterns
to access them. The code also includes the various helpers you can use to convert C types to
CQL types.

#### `todo.sql`

```SQL
-- This is a simple schema for keeping track of tasks and whether or not they have been completed

-- this serves to both declare the table and create the schema
create proc todo_create_tables()
begin
  create table if not exists tasks(
    description text!,
    done bool default false not null
  );
end;

-- adds a new not-done task
create proc todo_add(task text!)
begin
  insert into tasks values(task, false);
end;

-- gets the tasks in inserted order
create proc todo_tasks()
begin
  select rowid, description, done from tasks order by rowid;
end;

-- updates a given task by rowid
create proc todo_setdone_(rowid_ int!, done_ bool!)
begin
  update tasks set done = done_ where rowid == rowid_;
end;

-- deletes a given task by rowid
create proc todo_delete(rowid_ int!)
begin
  delete from tasks where rowid == rowid_;
end;
```

#### `main.c`

```c
#include <stdlib.h>
#include <sqlite3.h>

#include "todo.h"

int main(int argc, char **argv)
{
  /* Note: not exactly world class error handling but that isn't the point */

  // create a db
  sqlite3 *db;
  int rc = sqlite3_open(":memory:", &db);
  if (rc != SQLITE_OK) {
    exit(1);
  }

  // make schema if needed (in memory databases always begin empty)
  rc = todo_create_tables(db);
   if (rc != SQLITE_OK) {
    exit(2);
  }

  // add some tasks
  const char * const default_tasks[] = {
    "Buy milk",
    "Walk dog",
    "Write code"
  };

  for (int i = 0; i < 3; i++) {
    // note we make a string reference from a c string here
    cql_string_ref dtask = cql_string_ref_new(default_tasks[i]);
    rc = todo_add(db, dtask);
    cql_string_release(dtask); // and then dispose of the reference
    if (rc != SQLITE_OK) {
      exit(3);
    }
  }

  // mark a task as done
  rc = todo_setdone_(db, 1, true);
  if (rc != SQLITE_OK) {
    exit(4);
  }

  // delete a row in the middle, rowid = 2
  rc = todo_delete(db, 2);
  if (rc != SQLITE_OK) {
    exit(5);
  }

  // select out some results
  todo_tasks_result_set_ref result_set;
  rc = todo_tasks_fetch_results(db, &result_set);
  if (rc != SQLITE_OK) {
    printf("error: %d\n", rc);
    exit(6);
  }

  // get result count
  cql_int32 result_count = todo_tasks_result_count(result_set);

  // loop to print
  for (cql_int32 row = 0; row < result_count; row++) {
    // note "get" semantics mean that a ref count is not added
    // if you want to keep the string you must "retain" it
    cql_string_ref text = todo_tasks_get_description(result_set, row);
    cql_bool done = todo_tasks_get_done(result_set, row);
    cql_int32 rowid = todo_tasks_get_rowid(result_set, row);

    // convert to c string format
    cql_alloc_cstr(ctext, text);
    printf("%d: rowid:%d %s (%s)\n",
      row, rowid, ctext, done ? "done" : "not done");
    cql_free_cstr(ctext, text);
  }

  // done with results, free the lot
  cql_result_set_release(result_set);

  // and close the database
  sqlite3_close(db);
}
```

### Build Steps

```sh
# ${cgsql} refers to the root of the CG/SQL repo
% cql --in todo.sql --cg todo.h todo.c
% cc -o todo -I${cqsql}/sources main.c todo.c ${cgsql}/sources/cqlrt.c -lsqlite3
```

### Results

Note that rowid 2 has been deleted, the leading number is the index in
the result set. The rowid is of course the database rowid.

```
% ./todo
0: rowid:1 Buy milk (done)
1: rowid:3 Write code (not done)
```
