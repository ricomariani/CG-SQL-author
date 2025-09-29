/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include <cqlrt.h>

/*
 * This file declares helper functions for performing common operations such as
 * file handling and string manipulation in the context of CQL. They are
 * intended to alloc the creation of very simple command line tools.
*/

/*
 * Opens a file and returns a generic object reference to it. The file is
 * managed and finalized automatically. Returns NULL if the file cannot be
 * opened.
 */
cql_object_ref _Nullable cql_fopen(cql_string_ref _Nonnull name, cql_string_ref _Nonnull mode);

/*
 * Reads a single line from the file object. Returns the line as a string
 * reference, or NULL if the end of the file is reached.
 */
cql_string_ref _Nullable readline_object_file(cql_object_ref _Nonnull file_ref);

/*
 * Creates an argument list object from command-line arguments. Converts argc
 * and argv into a string list object for further processing.
 */
cql_object_ref _Nonnull create_arglist(int argc, char *_Nonnull *_Nonnull argv);

/*
 * Converts a substring of the input string to an integer. Starts at the
 * specified index and converts subsequent characters to an integer.
 */
cql_int32 atoi_at_text(cql_string_ref _Nullable text, cql_int32 index);

/*
 * Computes the length of the input string. Returns the number of characters in
 * the string.
 */
cql_int32 len_text(cql_string_ref _Nullable text);

/*
 * Retrieves the character (as an integer) at the specified index. Returns the
 * ASCII value of the character at the given position in the string.
 */
cql_int32 octet_text(cql_string_ref _Nullable text, cql_int32 index);

/*
 * Checks if the input string starts with the specified prefix. Returns true if
 * the haystack string begins with the needle string, false otherwise.
 */
cql_bool starts_with_text(cql_string_ref _Nonnull haystack, cql_string_ref _Nonnull needle);

/*
 * Checks if the haystack string contains the needle string at a specific index.
 * Returns true if the substring starting at the given index matches the needle
 * string.
 */
cql_bool contains_at_text(cql_string_ref _Nonnull haystack, cql_string_ref _Nonnull needle, cql_int32 index);

/*
 * Finds the index of the first occurrence of a substring. Searches for the
 * needle string within the haystack string and returns the starting index of
 * the first match, or -1 if no match is found.
 */
cql_int32 index_of_text(cql_string_ref _Nonnull haystack, cql_string_ref _Nonnull needle);

/*
 * Extracts a substring from the input string starting at a specific index and
 * with a given length. Returns a new string reference containing the specified
 * portion of the input string.
 */
cql_string_ref _Nonnull str_mid(cql_string_ref _Nonnull in, int startIndex, int length);

/*
 * Extracts the leftmost portion of the input string with the specified length.
 * Returns a new string reference containing the first 'length' characters of
 * the input string.
 */
cql_string_ref _Nonnull str_left(cql_string_ref _Nonnull in, int length);

/*
 * Extracts the rightmost portion of the input string with the specified length.
 * Returns a new string reference containing the last 'length' characters of the
 * input string.
 */
cql_string_ref _Nonnull str_right(cql_string_ref _Nonnull in, int length);
