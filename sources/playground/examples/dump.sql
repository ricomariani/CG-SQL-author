declare proc printf no check;

-- uses the new expressions as statements
-- also uses the new :: form to make pipelines

proc dump_int(x integer, out result integer)
begin
  set result := x;
  printf("%d\n", x);
end;

proc dump_text(x text, out result text)
begin
  set result := x;
  printf("%s\n", x);
end;

proc entrypoint()
begin
  1::dump();
  if 2::dump() then
    "hi there"::dump();
  end if;
end;
