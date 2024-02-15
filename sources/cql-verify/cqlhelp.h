#include <cqlrt.h>

cql_object_ref _Nullable cql_fopen(cql_string_ref _Nonnull name, cql_string_ref _Nonnull mode);
cql_string_ref _Nullable readline_object_file(cql_object_ref _Nonnull file_ref);
cql_object_ref _Nonnull create_arglist(int argc, char *_Nonnull *_Nonnull argv);

cql_int32 atoi_at_text(cql_string_ref _Nullable text, cql_int32 index);
cql_int32 len_text(cql_string_ref _Nullable text);
cql_int32 octet_text(cql_string_ref _Nullable text, cql_int32 index);
cql_bool starts_with_text(cql_string_ref _Nonnull haystack, cql_string_ref _Nonnull needle);
cql_bool contains_at_text(cql_string_ref _Nonnull haystack, cql_string_ref _Nonnull needle, cql_int32 index);
cql_int32 index_of_text(cql_string_ref _Nonnull haystack, cql_string_ref _Nonnull needle);

cql_string_ref str_mid(cql_string_ref in, int startIndex, int length);
cql_string_ref str_left(cql_string_ref in, int length);
cql_string_ref str_right(cql_string_ref in, int length);
