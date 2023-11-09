DECLARE PROC printf NO CHECK;

create procedure get_type_bool(value bool,        out result text not null) begin set result := "(bool)"; end;
create procedure get_type_int(value int,          out result text not null) begin set result := "(int)"; end;
create procedure get_type_long(value long,        out result text not null) begin set result := "(long)"; end;
create procedure get_type_real(value real,        out result text not null) begin set result := "(real)"; end;
create procedure get_type_text(value text,        out result text not null) begin set result := "(text)"; end;
create procedure get_type_object(value object,    out result text not null) begin set result := "(obj)"; end;
create procedure get_type_blob(value blob,        out result text not null) begin set result := "(blob)"; end;
create procedure get_type_null(value integer,     out result text not null) begin set result := "(null)"; end;

create procedure format_bool(value bool,        out result text not null) begin set result := case when value is null then "NULL" when value then "TRUE" else "FALSE" end; end;
create procedure format_int(value int,          out result text not null) begin set result := case when value is null then "NULL" else printf("%d", value) end; end;
create procedure format_long(value long,        out result text not null) begin set result := case when value is null then "NULL" else printf("%lld", value) end; end;
create procedure format_real(value real,        out result text not null) begin set result := case when value is null then "NULL" else printf("%g", value) end; end;
create procedure format_text(value text,        out result text not null) begin set result := case when value is null then "NULL" else value end; end;
create procedure format_object(value object,    out result text not null) begin set result := case when value is null then "NULL" else printf("%s", "[Object]") end; end;
create procedure format_blob(value blob,        out result text not null) begin set result := case when value is null then "NULL" else printf("%s", "[Blob]") end; end;
create procedure format_null(value integer,     out result text not null) begin set result := "NULL"; end;

create procedure dump_bool(value bool, out result bool)         begin set result := value; call printf("%-7s %s\n", value::get_type(), value::format()); end;
create procedure dump_int(value int, out result int)            begin set result := value; call printf("%-7s %s\n", value::get_type(), value::format()); end;
create procedure dump_long(value long, out result long)         begin set result := value; call printf("%-7s %s\n", value::get_type(), value::format()); end;
create procedure dump_real(value real, out result real)         begin set result := value; call printf("%-7s %s\n", value::get_type(), value::format()); end;
create procedure dump_text(value text, out result text)         begin set result := value; call printf("%-7s %s\n", value::get_type(), value::format()); end;
create procedure dump_object(value object, out result object)   begin set result := value; call printf("%-7s %s\n", value::get_type(), value::format()); end;
create procedure dump_blob(value blob, out result blob)         begin set result := value; call printf("%-7s %s\n", value::get_type(), value::format()); end;
create procedure dump_null(value integer, out result integer)   begin set result := value; call printf("%-7s %s\n", value::get_type(), value::format()); end;

@macro(stmt_list) DUMP!(x! expr)
begin
  printf("Dumping: `%s`:\n", @TEXT(x!));
  x!::dump();
  printf("\n");
end;

@macro(stmt_list) EXAMPLE_NOTE!(x! expr, note! expr)
begin
  call printf("%25s --> %-7s%-20.20s %s\n", @TEXT(x!), x!::get_type(), x!::format(), note!);
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
