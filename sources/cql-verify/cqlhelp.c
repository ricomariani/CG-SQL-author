/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/*
 * This file contains helper functions for performing common operations such as
 * file handling and string manipulation in the context of CQL. They are
 * intended to alloc the creation of very simple command line tools.
 *
 * Each function is documented below. They are all friendly to the CQL calling
 * conventions and use CQL runtime types.
*/

#include <alloca.h>
#include <stdio.h>
#include "cqlhelp.h"

/*
 * Finalizes and cleans up the file resource. This function acts as a destructor
 * for the file object, ensuring that the file is properly closed when no longer
 * needed.
 */
static void cql_file_finalize(void *_Nonnull data) {
  FILE *f = (FILE *)data;
  if (f) {
    fclose(f);
  }
}

/*
 * Retrieves the file pointer from the given file object reference. This
 * function extracts the underlying FILE* from the generic object.
 */
static FILE *_Nullable cql_file_get(cql_object_ref _Nonnull file_ref) {
  return (FILE *)_cql_generic_object_get_data(file_ref);
}

/*
 * Opens a file and wraps it in a generic object reference. This function
 * creates a file object that can be managed and finalized automatically.
 * Returns NULL if the file cannot be opened.
 */
cql_object_ref cql_fopen(cql_string_ref _Nonnull name, cql_string_ref mode) {

  // we need c strings to use fopen
  cql_alloc_cstr(n, name);
  cql_alloc_cstr(m, mode);

  FILE *f = fopen(n, m);

  cql_free_cstr(m, mode);
  cql_free_cstr(n, name);

  if (f) {
    return _cql_generic_object_create(f, cql_file_finalize);
  }
  else {
    return NULL;
  }
}

/*
 * Reads a single line from the file object. This function reads a line of text
 * from the file and returns it as a string reference. Returns NULL if the end
 * of the file is reached.
 */
cql_string_ref readline_object_file(cql_object_ref file_ref) {
  FILE *f = cql_file_get(file_ref);

  // this is not very robust... it's ok for 4k lines or less...
  char buf[4096];
  if (fgets(buf, sizeof(buf), f)) {
     size_t len = strlen(buf);

     // clobber the newline if we got one
     if (len) buf[len-1] = 0;
     return cql_string_ref_new(buf);
  }
  else {
     return NULL;
  }
}

/*
 * Extracts a substring starting from the specified index. This function returns
 * a new string reference containing the portion of the input string starting at
 * the given index.
 */
cql_string_ref after_text(cql_string_ref text, cql_int32 index) {
  cql_string_ref result = NULL;
  if (text) {
    cql_alloc_cstr(t, text);
    result = cql_string_ref_new(t + index);
    cql_free_cstr(t, text);
  }

  return result;
}

/*
 * Creates an argument list object from command-line arguments. This function
 * converts the given argc and argv into a string list object that can be used
 * in other parts of the program.
 */
cql_object_ref create_arglist(int argc, char **argv) {
  cql_object_ref arglist = cql_string_list_create();

  for (int i = 0; i < argc; i++) {
    cql_string_ref str_ref = cql_string_ref_new(argv[i]);
    cql_string_list_add(arglist, str_ref);

    // ownership transfered to the list
    cql_string_release(str_ref);
  }

  return arglist;
}

/*
 * Converts a substring of the input string to an integer. This function starts
 * at the specified index and converts the subsequent characters to an integer
 * value.
 */
cql_int32 atoi_at_text(cql_string_ref text, cql_int32 index) {
  cql_int32 result = 0;
  if (text) {
    cql_alloc_cstr(t, text);
    result = atoi(t + index);
    cql_free_cstr(t, text);
  }
  return result;
}

/*
 * Computes the length of the input string. This function returns the number of
 * characters in the string.
 */
cql_int32 len_text(cql_string_ref text) {
  cql_int32 result = 0;
  if (text) {
    cql_alloc_cstr(t, text);
    result = (cql_int32)strlen(t);
    cql_free_cstr(t, text);
  }
  return result;
}

/*
 * Retrieves the character (as an integer) at the specified index. This function
 * returns the ASCII value of the character at the given position in the string.
 */
cql_int32 octet_text(cql_string_ref text, cql_int32 index) {
  cql_int32 result = 0;
  if (text) {
    cql_alloc_cstr(t, text);
    result = t[index];
    cql_free_cstr(t, text);
  }
  return result;
}

/*
 * Checks if the input string starts with the specified prefix. This function
 * returns true if the haystack string begins with the needle string, and false
 * otherwise.
 */
cql_bool starts_with_text(
  cql_string_ref _Nonnull haystack,
  cql_string_ref _Nonnull needle)
{
  cql_alloc_cstr(h, haystack);
  cql_alloc_cstr(n, needle);

  size_t len = strlen(n);
  cql_bool result = strncmp(h, n, len) == 0;

  cql_free_cstr(n, needle);
  cql_free_cstr(h, haystack);

  return result;
}

/*
 * Finds the index of the first occurrence of a substring. This function
 * searches for the needle string within the haystack string and returns the
 * starting index of the first match, or -1 if no match is found.
 */
cql_int32 index_of_text(
  cql_string_ref _Nonnull haystack,
  cql_string_ref _Nonnull needle)
{
  cql_int32 result = -1;

  cql_alloc_cstr(h, haystack);
  cql_alloc_cstr(n, needle);

  const char *loc = strstr(h, n);

  if (loc) {
    result = (cql_int32)(loc - h);
  }

  cql_free_cstr(n, needle);
  cql_free_cstr(h, haystack);

  return result;
}

/*
 * Checks if the haystack string contains the needle string at a specific index.
 * This function returns true if the substring starting at the given index
 * matches the needle string, and false otherwise.
 */
cql_bool contains_at_text(
  cql_string_ref _Nonnull haystack,
  cql_string_ref _Nonnull needle,
  cql_int32 index)
{
  cql_alloc_cstr(h, haystack);
  cql_alloc_cstr(n, needle);

  size_t len = strlen(n);
  cql_bool result = strncmp(h + index, n, len) == 0;

  cql_free_cstr(n, needle);
  cql_free_cstr(h, haystack);

  return result;
}

/*
 * Extracts a substring from the input string starting at a specific index and
 * with a given length. This function returns a new string reference containing
 * the specified portion of the input string. If the start index is beyond the
 * input length, an empty string is returned.
 */
cql_string_ref str_mid(cql_string_ref in, int startIndex, int length) {
  cql_alloc_cstr(inStr, in);
  size_t inputLength = strlen(inStr);
  if (startIndex >= inputLength) {
    return cql_string_ref_new("");
  }

  size_t endIndex = (size_t)(startIndex + length);
  if (endIndex > inputLength) {
    endIndex = inputLength;
  }

  size_t outputLength = (size_t)(endIndex - (size_t)startIndex);
  char *temp = alloca(outputLength + 1); // +1 for null terminator

  strncpy(temp, inStr + startIndex, outputLength);
  temp[outputLength] = '\0'; // Null-terminate the output string

  cql_free_cstr(inStr, in);
  return cql_string_ref_new(temp);
}

/*
 * Extracts the leftmost portion of the input string with the specified length.
 * This function returns a new string reference containing the first 'length'
 * characters of the input string. If the length is less than or equal to zero,
 * an empty string is returned.
 */
cql_string_ref str_left(cql_string_ref in, int length_) {
  cql_alloc_cstr(inStr, in);
  size_t inputLength = strlen(inStr);
  if (length_ <= 0) {
    return cql_string_ref_new("");
  }
  size_t length = (size_t)length_;

  size_t outputLength = (length < inputLength) ? length : inputLength;
  char *temp = alloca(outputLength + 1); // +1 for null terminator

  strncpy(temp, inStr, outputLength);
  temp[outputLength] = '\0'; // Null-terminate the output string

  cql_free_cstr(inStr, in);
  return cql_string_ref_new(temp);
}

/*
 * Extracts the rightmost portion of the input string with the specified length.
 * This function returns a new string reference containing the last 'length'
 * characters of the input string. If the length is less than or equal to zero,
 * an empty string is returned.
 */
cql_string_ref str_right(cql_string_ref in, int length_) {
  cql_alloc_cstr(inStr, in);
  size_t inputLength = strlen(inStr);
  if (length_ <= 0) {
    return cql_string_ref_new("");
  }

  size_t length = (size_t)length_;

  size_t startIndex = (inputLength > length) ? inputLength - length : 0;
  size_t outputLength = (startIndex < inputLength) ? inputLength - startIndex : 0;
  char *temp = alloca(outputLength + 1); // +1 for null terminator

  strncpy(temp, inStr + startIndex, outputLength);
  temp[outputLength] = '\0'; // Null-terminate the output string

  cql_free_cstr(inStr, in);
  return cql_string_ref_new(temp);
}
