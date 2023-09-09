
DECLARE PROC printf NO CHECK;

proc fmt_bool(x bool, out result text)
begin
   set result := case when x is null then "null" when x then "true" else "false" end;
end;

proc fmt_int(x int, out result text)
begin
   set result := case when x is null then "null" else printf("%d", x) end;
end;

proc fmt_long(x long, out result text)
begin
   set result := case when x is null then "null" else printf("%lld", x) end;
end;

proc fmt_real(x real, out result text)
begin
   set result := case when x is null then "null" else printf("%g", x) end;
end;

proc fmt_text(x text, out result text)
begin
   set result := case when x is null then "null" else x end;
end;

-- you could do something for blob and object too if you wanted

CREATE PROC entrypoint ()
BEGIN
  let i := true;
  let j := 5;
  let k := 32L;
  let l := 3.14;
  let m := "foo";
  call printf("bool:%s int:%s long:%s real:%s text:%s\n", i::fmt(), j::fmt(), k::fmt(), l::fmt(), m::fmt());
END;
