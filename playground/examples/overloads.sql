
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

#define DUMP(expr)  printf("%20s -> %s\n", #expr, (expr)::fmt())
#define NOTE(expr, note)  printf("%20s -> %s (%s)\n", #expr, (expr)::fmt(), note)

proc dump_examples()
begin
  declare _null bool;
  set _null := null;
  printf("\n");
  DUMP(1 + 1);
  DUMP(1 + NULL);
  DUMP(5 / 2);
  DUMP(5 % 2);
  DUMP(true and NULL);
  DUMP(false and NULL);
  DUMP(true or NULL);
  DUMP(false or NULL);
  NOTE(1 | 2 & 6, "this is not 3, because | and & have equal precedence in SQL");
  NOTE((1 | 2) & 6, "with no parens it means this version");
  NOTE(1 | (2 & 6), "this requires parens in SQL and CQL");
  DUMP(1 + 3 * 2);
  DUMP((1 + 3) * 2);
  DUMP(true);
  DUMP(false);
  DUMP(not null);
  DUMP(not true);
  DUMP(not false);
  NOTE(_null == 1, "hence not true");
  NOTE(_null == _null, "hence not true");
  DUMP("x" == "x");
  DUMP(1 is 1);
  DUMP(2 is 1);
  DUMP(null is 1);
  DUMP(null is null);
  DUMP("x" is "x");
  DUMP(2 between 1 and 3);
  DUMP(3 between 1 and 2);
  DUMP(5 in (1, 2, 3, 4, 5));
  DUMP(7 in (1, 2));
  DUMP(7 not in (1, 2));
  DUMP(null in (1, 2, 3));
  NOTE(null in (1, null, 3), "null == null is not true");
end;

proc entrypoint ()
begin
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
  printf("bool:%s int:%s long:%s real:%s text:%s\n", b::fmt(), i::fmt(), l::fmt(), r::fmt(), t::fmt());

  -- fmt_bool handles null too
  set b := null;
  printf("bool:%s\n", b::fmt());

  -- using type kind to further specify which formatter
  declare energy real<joules>;
  set energy := 100.5;
  declare weight real<pounds>;
  set weight := 203;

  printf("arg1: %s arg2: %s\n", energy:::fmt(), weight:::fmt());

  dump_examples();
end;
