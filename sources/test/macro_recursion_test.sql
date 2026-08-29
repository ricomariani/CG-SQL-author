@macro(expr) direct!()
begin
  direct!()
end;

@macro(expr) cycle_a!()
begin
  cycle_b!()
end;

@macro(expr) cycle_b!()
begin
  cycle_a!()
end;

let direct_result := direct!();
let indirect_result := cycle_a!();
