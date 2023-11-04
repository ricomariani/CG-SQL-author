@macro(expr) exp!(e! expr)
begin
  e! + @macro_line
end;

let z := exp!();
let z := exp!(1,2);

@LINE+exp!(1);

let z := exp!(select(1 x));

@ID(@TEXT("foo bar"));

@ID(@TEXT(" foo"));

@ID(@TEXT(""));

@macro(expr) sel1!()
begin
  exp!(select(1 x))
end;

@macro(expr) sel2!()
begin
  sel1!()
end;

@macro(expr) sel3!()
begin
  sel2!()
end;

sel3!();
