
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

proc fmt_real_pounds(x real<pounds>, out result text)
begin
   set result := case when x is null then "null" else printf("%glbs", x) end;
end;

proc fmt_real_joules(x real<joules>, out result text)
begin
   set result := case when x is null then "null" else printf("%gJ", x) end;
end;

-- you could do something for blob and object too if you wanted

CREATE PROC entrypoint ()
BEGIN
  declare b bool;
  set b := true;
  let i := 5;
  let l := 32L;
  let r := 3.14;
  let t := "foo";
  -- this is only needed if null values are a possibility
  -- otherwise the format string would work by itself
  -- ::fmt converts the data to a string even if it's null
  -- the normal runtime can't do that
  call printf("bool:%s int:%s long:%s real:%s text:%s\n", b::fmt(), i::fmt(), l::fmt(), r::fmt(), t::fmt());

  -- fmt_bool handles null too
  set b := null;
  call printf("bool:%s\n", b::fmt());

  -- using type kind to further specify which formatter
   declare energy real<joules>;
   set energy := 100.5;
   declare weight real<pounds>;
   set weight := 203;

  call printf("arg1: %s arg2: %s\n", energy:::fmt(), weight:::fmt());
END;
