/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

-- This is a simple schema for keep track of tasks and whether they are done

-- this serves to both declare the table and create the schema
proc todo_create_tables ()
begin
  create table if not exists tasks(
    description text!,
    done bool! default false
  );
end;

-- adds a new not-done task
proc todo_add (task text!)
begin
  insert into tasks
    values(task, false);
end;

-- gets the tasks in inserted order
proc todo_tasks ()
begin
  select rowid, description, done
    from tasks
    order by rowid;
end;

-- updates a given task by rowid
proc todo_setdone_ (rowid_ int!, done_ bool!)
begin
  update tasks
    set done = done_
    where rowid = rowid_;
end;

-- deletes a given task by rowid
proc todo_delete (rowid_ int!)
begin
  delete from tasks where rowid = rowid_;
end;
