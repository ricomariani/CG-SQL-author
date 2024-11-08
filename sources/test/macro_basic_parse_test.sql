@macro (expr) foo! (x! expr, z! expr)
begin
  x! + z!
end;

@macro(stmt_list) bar!(x! expr, y! stmt_list)
begin
  if x! then y!; end if;
end;

var x_int int!;

create proc foo()
begin
  bar!(1, begin call printf("hi\n"); end);
end;

create table xx(
  x int!
);

create table yy(
  y int!
);

@macro(query_parts) qp!()
begin
  xx as T1 inner join yy as T2 on T1.x == T2.y
end;

@macro(stmt_list) sel!(e! expr, q! query_parts)
begin
  select e! from q! as Q;
end;

select * from qp!() inner join yy;

select * from qp!() as T1;

sel!(x, from( qp!() ) );

select * from qp!() as T1;

@macro(cte_tables) cte!()
begin
  foo(*) as (select 1 x, 2 y),
  bar(*) as (select 3 u, 4 v)
end;

with
vv(*) as (select 1 x, 2 y),
cte!(),
uu(*) as (select 1 x, 2 y)
select * from foo;

with
cte!(),
uu(*) as (select 1 x, 2 y)
select * from foo;

with
cte!()
select * from foo;

with
vv(*) as (select 1 x, 2 y),
cte!()
select * from foo;


@macro(stmt_list) query!(u! cte_tables)
begin
  with u! select * from foo;
end;

query!(with( foo(*) as (select 100 x, 200 y)));

@macro(select_core) selcor!(x! expr)
begin
  select x! + 1 x
  union all
  select x! + 2 x
end;

@macro(select_core) selcor2!(x! select_core)
begin
   ROWS(x!) union all ROWS(x!)
end;

ROWS(selcor2!(selcor!(5)));

@macro(select_expr) se!(x! select_expr)
begin
  x!, x!
end;

@macro(select_expr) se2!(x! select_expr)
begin
  se!(select(x!))
end;

select se2!(select(x+2 z));

@macro(stmt_list) assert!(e! expr)
begin
  if (not e!) then
     call printf("assert '%s' failed at line %s:%d\n", @TEXT(e!), @MACRO_FILE, @MACRO_LINE);
  end if;
end;

@macro(expr) macro1!(u! expr)
begin
  u! + u! +1
end;

@macro(expr) macro2!(u! expr, v! expr)
begin
  u! * macro1!(v! + 5)
end;

@macro(expr) macro3!(q! query_parts)
begin
  @TEXT(q!)
end;

@macro(expr) macro4!(q! cte_tables)
begin
  @TEXT(q!)
end;

@macro(expr) macro5!(q! select_core)
begin
  @TEXT(q!)
end;

@macro(expr) macro6!(q! expr)
begin
  @TEXT(q!)
end;

@macro(expr) macro7!(q! select_expr)
begin
  @TEXT(q!)
end;

let x := 1;
let y := 2;
let z := macro2!(x, y);

set z := @LINE;


let zz := macro3!(from( (select 1 x, 2 y) as T));
set zz := macro3!(from( T1 join T2 on T1.id = T2.id));
set zz := macro4!(WITH( x(*) as (select 1 x, 2 y) ));
set zz := macro5!(ROWS(select 1 x from foo));
set zz := macro6!(1+2);
set zz := macro7!(select(1 x, 2 y));

let zzz := @TEXT("begin\n", assert!(7), "\nfoo");
set @ID("x") := 5;
let @ID(@TEXT("u", "v")) := 5;
set @ID(w,x,y,z) := 6;
set @ID(wx) := 7;

@macro(stmt_list) mondo1!(a! expr, b! query_parts, c! select_core, d! select_expr, e! cte_tables, f! stmt_list)
begin
  set zz := @text(a!, b!, c!, d!, e!, f!);
end;

@macro(stmt_list) mondo2!(a! expr, b! query_parts, c! select_core, d! select_expr, e! cte_tables, f! stmt_list)
begin
  mondo1!(a!, b!, c!, d!, e!, f!);
end;

mondo2!(1+2, from(x join y), rows(select 1 from foo union select 2 from bar), select(20 xx),
  with(f(*) as (select 99 from yy)), begin let qq := 201; end);

-- make sure these are ok to use as identifiers
let expr := 1;
let stmt_list := 2;
let query_parts := 3;
let select_core := 4;
let select_expr := 5;
let cte_tables := 6;

@macro(expr) a_selection!()
begin
  (select 1+5)
end;

let x := @TEXT(a_selection!());

@macro(stmt_list) file_line!()
begin
  let line := @MACRO_LINE;
  let file := @MACRO_FILE;
end;

let z := @TEXT(1+5);
