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
