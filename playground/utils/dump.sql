DECLARE PROC printf NO CHECK;

@macro(stmt_list) dumper_procs!(t! expr, eval! expr)
begin
  -- this generates a procedure called (e.g.) get_type_bool that returns the type
  proc @ID("get_type_", t!)(value @ID(t!), out result text not null)
  begin
     set result := @TEXT("(", t!, ")");
  end;

  -- this generates a procedure called (e.g.) format_bool returns the value as text
  proc @ID("format_", t!)(value @ID(t!), out result text not null)
  begin
    set result := case
     when value is null then "NULL"
     else eval!
     end;
  end;

  @op @ID(t!) : call format as @ID("format_", t!);
  @op @ID(t!) : call get_type as @ID("get_type_", t!);

  -- this generates a procedure called (e.g.) dump_bool prints the type and value
  proc @ID("dump_", t!)(value @ID(t!), out result @ID(t!))
  begin
    set result := value;
    call printf("%-7s %s\n", value:get_type, value:format);
  end;

  @op @ID(t!) : call dump as @ID("dump_", t!);

end;

dumper_procs!("bool", case when value then "TRUE" else "FALSE" end);
dumper_procs!("int", printf("%d", value));
dumper_procs!("long", printf("%lld", value));
dumper_procs!("real", printf("%g", value));
dumper_procs!("text", value);
dumper_procs!("object", "[Object]");
dumper_procs!("blob", "[Blob]");

@op NULL : call dump as dump_null;
@op NULL : call format as format_null;
@op NULL : call get_type as get_type_null;

proc format_null(value int, out result text!) 
begin
  result := "NULL";
end;

proc get_type_null(value int, out result text!) 
begin
  result := '("null")';
end;

proc dump_null(value int)
begin
  call printf("%-7s %s\n", null:get_type(), null:format());
end;

@macro(stmt_list) DUMP!(x! expr)
begin
  printf("Dumping: `%s`:\n", @TEXT(x!));
  x!:dump();
  printf("\n");
end;

@macro(stmt_list) EXAMPLE_NOTE!(x! expr, note! expr)
begin
  call printf("%25s --> %-7s%-20.20s %s\n", @TEXT(x!), x!:get_type, x!:format, note!);
end;

@macro(stmt_list) EXAMPLE!(x! expr)
begin
  EXAMPLE_NOTE!(x!, "");
end;

@macro(stmt_list) ERROR!(x! expr, note! expr)
begin
  call printf("%25s --> ERROR %s\n", @TEXT(x!), note!);
end;

@macro(stmt_list) _!(x! expr)
begin
  printf("%s\n", x!);
end;
