select func foofoo(x integer) integer;
create table foo(id integer, x text);

create proc stuff()
begin
  select * from foo where foofoo(id) > 5;
end;
