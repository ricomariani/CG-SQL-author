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

// Helper macros for counting arguments
#define COUNT_ARGS(...) COUNT_ARGS_(__VA_ARGS__, 5, 4, 3, 2, 1)
#define COUNT_ARGS_(a1, a2, a3, a4, a5, count, ...) count

// Macro with different behaviors based on the number of arguments
#define EXAMPLE(...) EXAMPLE_(COUNT_ARGS(__VA_ARGS__), __VA_ARGS__)
#define EXAMPLE_(...) EXAMPLE_N(__VA_ARGS__)
#define EXAMPLE_N(N,...) EXAMPLE_ ## N (__VA_ARGS__)

#define ERROR(...) ERROR_(COUNT_ARGS(__VA_ARGS__), __VA_ARGS__)
#define ERROR_(...) ERROR_N(__VA_ARGS__)
#define ERROR_N(N,...) ERROR_ ## N (__VA_ARGS__)

#define EXAMPLE_1(x) call printf("%25s --> %-7s%-20.20s\n", #x, (x)::get_type(), (x)::format())
#define EXAMPLE_2(x, y) call printf("%25s --> %-7s%-20.20s %s\n", #x, (x)::get_type(), (x)::format(), y)

#define ERROR_1(x) call printf("%25s --> ERROR\n", #x)
#define ERROR_2(x, y) call printf("%25s --> ERROR %s\n", #x, y)

#define _(...) print_any(COUNT_ARGS(__VA_ARGS__), __VA_ARGS__)
#define print_any(...) print_N(__VA_ARGS__)
#define print_N(N, ...) print_ ## N(__VA_ARGS__)
#define print_1(str) call printf("%s\n", str)
#define print_2(fmt, a) call printf(fmt "\n", a)
#define print_3(fmt, a, b) call printf(fmt "\n", a, b)
#define print_4(fmt, a, b, c) call printf(fmt "\n", a, b, c)
#define print_5(fmt, a, b, c, d) call printf(fmt "\n", a, b, c, d)
