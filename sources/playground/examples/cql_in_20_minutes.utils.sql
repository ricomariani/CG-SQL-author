DECLARE PROC printf NO CHECK;

create procedure get_type_bool(value BOOL, out result text not null)     begin set result := "(bool)"; end;
create procedure get_type_int(value INT, out result text not null)       begin set result := "(int)"; end;
create procedure get_type_long(value long, out result text not null)     begin set result := "(long)"; end;
create procedure get_type_real(value real, out result text not null)     begin set result := "(real)"; end;
create procedure get_type_text(value text, out result text not null)     begin set result := "(text)"; end;
create procedure get_type_object(value object, out result text not null) begin set result := "(obj)"; end;
create procedure get_type_blob(value blob, out result text not null)     begin set result := "(blob)"; end;
create procedure get_type_null(value integer, out result text not null)  begin set result := "(null)"; end;

create procedure format_bool(value BOOL, out result text not null)     begin set result := case when value is null then "NULL" when value then "TRUE" else "FALSE" end; end;
create procedure format_int(value INT, out result text not null)       begin set result := case when value is null then "NULL" else printf("%d", value) end; end;
create procedure format_long(value long, out result text not null)     begin set result := case when value is null then "NULL" else printf("%lld", value) end; end;
create procedure format_real(value real, out result text not null)     begin set result := case when value is null then "NULL" else printf("%g", value) end; end;
create procedure format_text(value text, out result text not null)     begin set result := case when value is null then "NULL" else value end; end;
create procedure format_object(value object, out result text not null) begin set result := case when value is null then "NULL" else printf("%s", "[Object]") end; end;
create procedure format_blob(value blob, out result text not null)     begin set result := case when value is null then "NULL" else printf("%s", "[Blob]") end; end;
create procedure format_null(value integer, out result text not null)  begin set result := "NULL"; end;

@echo c, "#pragma clang diagnostic ignored \"-Wformat-extra-args\"";
#define EXAMPLE(x, ...) call printf("%25s --> %-7s%-20.20s %s\n", #x, (x)::get_type(), (x)::format(), ##__VA_ARGS__, "")
#define ERROR(x, ...) call printf("%25s --> ERROR %s\n", #x, ##__VA_ARGS__, "")
#define _(...) call printf(__VA_ARGS__); call printf("\n")
