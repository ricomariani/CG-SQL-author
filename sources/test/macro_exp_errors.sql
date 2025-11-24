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

unknown_macro!();

unknown_arg!;

exp!(not_valid_arg!);

exp!(not_valid_macro!());

-- correct version
@macro(stmt_list) all_slots1!(a! expr, b! query_parts, c! select_core, d! select_expr, e! cte_tables, f! stmt_list)
begin
  if a! then
    f!;
  else
    with e! select d! from b! union all rows(c!);
  end if;
end;

all_slots1!(
  1+2,
  from(x join y),
  rows(select 1 from foo union select 2 from bar),
  select(20 xx),
  with(f(*) as (select 99 from yy)),
  begin let qq := 201; end
  );

-- invalid query parts
@macro(stmt_list) all_slots2!(a! expr, b! query_parts, c! select_core, d! select_expr, e! cte_tables, f! stmt_list)
begin
  if a! then
    f!;
  else
    with e! select d! from c! union all rows(c!);
  end if;
end;

all_slots2!(
  1+2,
  from(x join y),
  rows(select 1 from foo union select 2 from bar),
  select(20 xx),
  with(f(*) as (select 99 from yy)),
  begin let qq := 201; end
  );

-- invalid statment list
@macro(stmt_list) all_slots3!(a! expr, b! query_parts, c! select_core, d! select_expr, e! cte_tables, f! stmt_list)
begin
  if a! then
    f!;
  else
    with e! select d! from f! union all rows(c!);
  end if;
end;

all_slots3!(
  1+2,
  from(x join y),
  rows(select 1 from foo union select 2 from bar),
  select(20 xx),
  with(f(*) as (select 99 from yy)),
  begin let qq := 201; end
  );

-- invalid cte_tables
@macro(stmt_list) all_slots4!(a! expr, b! query_parts, c! select_core, d! select_expr, e! cte_tables, f! stmt_list)
begin
  if a! then
    f!;
  else
    with e! select d! from e! union all rows(c!);
  end if;
end;

all_slots4!(
  1+2,
  from(x join y),
  rows(select 1 from foo union select 2 from bar),
  select(20 xx),
  with(f(*) as (select 99 from yy)),
  begin let qq := 201; end
  );

-- invalid select_expr
@macro(stmt_list) all_slots5!(a! expr, b! query_parts, c! select_core, d! select_expr, e! cte_tables, f! stmt_list)
begin
  if a! then
    f!;
  else
    with e! select d! from d! union all rows(c!);
  end if;
end;

all_slots5!(
  1+2,
  from(x join y),
  rows(select 1 from foo union select 2 from bar),
  select(20 xx),
  with(f(*) as (select 99 from yy)),
  begin let qq := 201; end
  );

-- invalid query_parts
@macro(stmt_list) all_slots6!(a! expr, b! query_parts, c! select_core, d! select_expr, e! cte_tables, f! stmt_list)
begin
  if a! then
    b!;
  else
    with e! select d! from b! union all rows(c!);
  end if;
end;

all_slots6!(
  1+2,
  from(x join y),
  rows(select 1 from foo union select 2 from bar),
  select(20 xx),
  with(f(*) as (select 99 from yy)),
  begin let qq := 201; end
  );

-- invalid expr
@macro(stmt_list) all_slots7!(a! expr, b! query_parts, c! select_core, d! select_expr, e! cte_tables, f! stmt_list)
begin
  if a! then
    f!;
  else
    with a! select d! from b! union all rows(c!);
  end if;
end;

all_slots7!(
  1+2,
  from(x join y),
  rows(select 1 from foo union select 2 from bar),
  select(20 xx),
  with(f(*) as (select 99 from yy)),
  begin let qq := 201; end
  );

-- no proc
let z := @proc;

create proc error_proc()
begin
  not_a_real_macro!;
end;
