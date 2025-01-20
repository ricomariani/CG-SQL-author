-- this test file has to be in a different directory to exercise the include paths directives

@include "test2_second_include_file.sql"

proc any_proc(out z integer)
begin
  z := 1;
end;
