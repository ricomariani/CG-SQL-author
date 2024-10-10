@include "utils/timer.sql"

DECLARE PROC printf NO CHECK;

declare enum gender_type integer ( male = 0, female = 1, other );

CREATE PROC User(id int, name text, gender gender_type, birth_year int)
BEGIN
  declare C cursor like User arguments;
  fetch C from arguments;
  out union C;
END;

CREATE PROC Nested_User_2(LIKE User)
BEGIN
  declare C cursor for call User(from arguments);
  fetch C;
  out union C;
END;

CREATE PROC Nested_User_3(LIKE User)
BEGIN
  declare C cursor for call Nested_User_2(from arguments);
  fetch C;
  out union C;
END;

CREATE PROC Nested_User_4(LIKE User)
BEGIN
  declare C cursor for call Nested_User_3(from arguments);
  fetch C;
  out union C;
END;

CREATE PROC Nested_User_5(LIKE User)
BEGIN
  declare C cursor for call Nested_User_4(from arguments);
  fetch C;
  out union C;
END;

CREATE PROC decode_encoded_user(encoded_user object<encoded_user>)
BEGIN
  cursor C for call User(1, "Bob", gender_type.male, 1990);
  fetch C;
  out union C;
END;

@op object<encoded_user> : call decode as decode_encoded_user;

CREATE PROC user_and_themselves(user_boxed object<decode_encoded_user set>)
BEGIN
  cursor C for user_boxed;
  fetch C;

  out union
    call User(C.id, C.name, C.gender, C.birth_year) join
    call User(C.id, C.name, C.gender, C.birth_year) using (id) AS subUser1 and
    call User(C.id, C.name, C.gender, C.birth_year) using (id) AS subUser2 and
    call User(C.id, C.name, C.gender, C.birth_year) using (id) AS subUser3 and
    call User(C.id, C.name, C.gender, C.birth_year) using (id) AS subUser4 and
    call User(C.id, C.name, C.gender, C.birth_year) using (id) AS subUser5
  ;
END;

@macro(stmt_list) bench!(name! expr, s! stmt_list)
begin
  i := 0;
  timer:start();
  while i <= number_of_iterations
  begin
    s!;
    i += 1;
  end;
  timer:stop();
  printf("Timings for calling %s:\n", name!);
  timer:print();
  printf("\n\n");
end;

@attribute(playground:not_implemented_in_lua)
CREATE PROC entrypoint ()
BEGIN
  let timer := create_timer();
  let i := 0;

  let number_of_iterations := 1000000;
  printf("Context:\nNumber of iterations: %d\n\n", number_of_iterations);

  bench!("Fetching Like  User from values",
  begin
    declare C1 cursor LIKE User;
    fetch C1 FROM VALUES(1, "Bob", gender_type.male, 1990);
  end);

  bench!("calling User",
  begin
    let user_boxed_1 := User(1, "Bob", gender_type.male, 1990);
  end);

  bench!("calling Nested_user_5()",
  begin
    let user_boxed_2 := Nested_User_5(1, "Bob", gender_type.male, 1990);
  end);



  declare encoded_user OBJECT<encoded_user>;
  let user_boxed := encoded_user:decode();

  bench!("calling user_and_themselves",
  begin
      cursor C2 for call user_and_themselves(user_boxed);
      fetch C2;
  end);

end;

