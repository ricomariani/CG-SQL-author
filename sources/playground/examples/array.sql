declare proc printf no check;

proc make_schema()
begin
  printf("creating schema\n");
  create table tasks (
    task_id int not null primary key,
    name text not null,
    notes text not null
  );

  printf("inserting data\n");
  insert into tasks values
           (1, "T1", "notes for 1"),
           (2, "T2", "notes for 2"),
           (3, "T3", "notes for 3");
  printf("tasks table ready\n");
end;

/* this is a terrible idea never do this for real, it's just a demo
   in the name of all you hold dear do not copy and paste this code */
proc get_from_int_task_id(task_id_ integer not null, field text not null, out value text not null)
begin
  cursor C for select * from tasks where task_id = task_id_;
  fetch C;

  value := ifnull(case when field == "name" then C.name when field == "notes" then C.notes  end, "unknown");
end;

proc entrypoint()
begin
  make_schema();
  declare id int<task_id>;
  id := 0;
  while id <= 4
  begin
    printf("%d %s %s\n", id, id['name'], id['notes']);
    id += 1;
  end;
end;
