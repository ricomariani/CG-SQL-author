declare proc printf no check;

-- make two kludgy globals to hold the state
declare _names cql_string_list;
declare _notes cql_string_list;

proc init_data()
begin
  -- this kind of sharded representation is not recommended
  -- but it makes a fine sample showing how you could do things
  -- with atypical objects.  Imagine what you could do with
  -- native callbacks and an HWND
  _names := create_cql_string_list();
  _notes := create_cql_string_list();

  let i := 0;
  while i <= 3
  begin
    _names:::add(printf("T%d", i));
    _notes:::add(printf("notes for %d", i));
    i += 1;
  end;
end;

proc get_from_int_task_id(task_id integer! , field text! , out value text!)
begin
  -- we have to do this to make sure we don't get a warning for uninitialized variables
  let names := ifnull_throw(_names);
  let notes := ifnull_throw(_notes);

  value := ifnull(
  case
    when task_id < 0 or task_id >= names.count then null
    when field == "name" then names[task_id]
    when field == "notes" then notes[task_id]
  end, "unknown");
end;

proc set_in_int_task_id(task_id integer not null, field text not null, value text not null)
begin
  -- we have to do this to make sure we don't get a warning for uninitialized variables
  let names := ifnull_throw(_names);
  let notes := ifnull_throw(_notes);

  if task_id < 0 or task_id >= names.count return;

  if field == "name" then
     names[task_id] := value;
  else if field == "notes" then
     notes[task_id] := value;
  end if;
end;

proc entrypoint()
begin
  init_data();
  declare id int<task_id>;

  printf("\nenumerating with array syntax\n\n");
  id := -1;
  while id <= 4
  begin
    printf("%d %20s %20s\n", id, id['name'], id['notes']);
    id += 1;
  end;

  printf("\nnow the same thing with property syntax.\n\n");
  id := -1;
  while id <= 4
  begin
    printf("%d %20s %20s\n", id, id.name, id.notes);
    id += 1;
  end;

  printf("\nupdating values with some array and property jazz\n");

  printf("task1: name := T1*\n");
  id := 1;
  id.name := "T1*";

  printf("task3: notes := notes for 3*\n");
  id := 3;
  id.notes := "notes for 3*";

  printf("\nnow we view the changes\n\n");
  id := -1;
  while id <= 4
  begin
    printf("%d %20s %20s\n", id, id.name, id.notes);
    id += 1;
  end;
end;
