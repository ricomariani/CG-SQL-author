/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include "cql.h"
#include "charbuf.h"
#include "encoders.h"

// This converts from SQL string literal format to plain output
// Note that SQL string literal have no escapes except for double quote
cql_noexport void cg_decode_string_literal(CSTR str, charbuf *output) {
  const char quote = '\'';
  CSTR p = str+1;  // the first character is the quote itself

  while (p[0]) {
    if (p[0] == quote && p[1] == quote) {
      bputc(output, quote);
      p++;
    }
    else if (p[0] == quote) {
      break;
    }
    else {
      bputc(output, p[0]);
    }
    p++;
  }
}

// This converts from a plain string to sql string literal
// Note SQL string literals have no escape sequences other than '' -> '
cql_noexport void cg_encode_string_literal(CSTR str, charbuf *output) {
  const char quote = '\'';
  const char *p = str;

  bputc(output, quote);

  for ( ;p[0]; p++) {
    if (p[0] == quote) bputc(output, quote);
    bputc(output, p[0]);
  }

  bputc(output, quote);
}

// Keep hex emission deterministic and lowercase; the contract guards against
// out-of-range nibble input so callers can rely on exact two-digit escapes.
static void emit_hex_digit(uint32_t ch, charbuf *output) {
  Contract(ch >= 0 && ch <= 15);
  if (ch < 10) {
    bputc(output, (char)(ch + '0'));
  }
  else {
    bputc(output, (char)(ch - 10 + 'a'));
  }
}

// This converts from a plain string to C string literal
cql_noexport void cg_encode_char_as_c_string_literal(char c, charbuf *output) {
  const char quote = '"';
  const char backslash = '\\';

  switch (c) {
    case '\"':  bputc(output, backslash); bputc(output, quote); break;
    case '\a':  bputc(output, backslash); bputc(output, 'a'); break;
    case '\b':  bputc(output, backslash); bputc(output, 'b'); break;
    case '\f':  bputc(output, backslash); bputc(output, 'f'); break;
    case '\n':  bputc(output, backslash); bputc(output, 'n'); break;
    case '\r':  bputc(output, backslash); bputc(output, 'r'); break;
    case '\t':  bputc(output, backslash); bputc(output, 't'); break;
    case '\v':  bputc(output, backslash); bputc(output, 'v'); break;
    case '\\':  bputc(output, c); bputc(output, c); break;
    default  :
      // note: 0x80 - 0xff will be negative and are hence covered by this test
      if (c < 32) {
        uint32_t ch = (uint32_t)c;
        ch &= 0xff;
        bprintf(output, "\\x");
        emit_hex_digit(ch >> 4, output);
        emit_hex_digit(ch & 0xf, output);
      }
      else {
        bputc(output, c);
      }
  }
}

// This converts from a plain string to json string literal (fewer escapes available/needed)
//
// From the spec, the valid single escape characters are
// SingleEscapeCharacter :: one of
//      ' " \ b f n r t v
//
// \v should be legal but it is avoided because the python validator
// doesn't support it. We generate all of the others if needed
// but \' is never needed as we always use double quotes.
//
// likewise the spec says:
//
// UnicodexEscapeSequence ::
//      u HexDigit HexDigit HexDigit HexDigit
//
cql_noexport void cg_encode_char_as_json_string_literal(char c, charbuf *output) {
  const char quote = '"';
  const char backslash = '\\';

  switch (c) {
    case '\"':  bputc(output, backslash); bputc(output, quote); break;
    case '\\':  bputc(output, c); bputc(output, c); break;
    case '\b':  bputc(output, backslash); bputc(output, 'b'); break;
    case '\f':  bputc(output, backslash); bputc(output, 'f'); break;
    case '\n':  bputc(output, backslash); bputc(output, 'n'); break;
    case '\r':  bputc(output, backslash); bputc(output, 'r'); break;
    case '\t':  bputc(output, backslash); bputc(output, 't'); break;
    default  :
      // note: 0x80 - 0xff will be negative and are hence covered by this test
      if (c < 32) {
        uint32_t ch = (uint32_t)c;
        ch &= 0xff;
        bprintf(output, "\\u00");
        emit_hex_digit(ch >> 4, output);
        emit_hex_digit(ch & 0xf, output);
      }
      else {
        bputc(output, c);
      }
  }
}

// This converts from a plain string to C string literal
cql_noexport void cg_encode_c_string_literal(CSTR str, charbuf *output) {
  const char quote = '"';
  const char *p = str;

  bputc(output, quote);

  for ( ;p[0]; p++) {
    cg_encode_char_as_c_string_literal(p[0], output);
  }
  bputc(output, quote);
}

// Returns the expected length of a UTF-8 sequence based on its lead byte.
// Returns 0 if the byte is not a valid UTF-8 lead byte.
static int32_t utf8_sequence_length(unsigned char lead_byte) {
  if ((lead_byte & 0x80) == 0x00) return 1;       // 0xxxxxxx - ASCII
  if ((lead_byte & 0xE0) == 0xC0) return 2;       // 110xxxxx - 2-byte sequence
  if ((lead_byte & 0xF0) == 0xE0) return 3;       // 1110xxxx - 3-byte sequence
  if ((lead_byte & 0xF8) == 0xF0) return 4;       // 11110xxx - 4-byte sequence
  return 0;  // Invalid lead byte (continuation byte or invalid)
}

// Checks if a byte is a valid UTF-8 continuation byte (10xxxxxx)
static bool_t is_utf8_continuation(unsigned char byte) {
  return (byte & 0xC0) == 0x80;
}

// Validates a complete UTF-8 sequence starting at p.
// Returns the sequence length if valid, 0 if invalid.
static int32_t valid_utf8_sequence(const unsigned char *p) {
  int32_t len = utf8_sequence_length(p[0]);
  if (len == 0) return 0;  // Invalid lead byte
  if (len == 1) return 1;  // ASCII, always valid

  // Check that we have the right number of valid continuation bytes
  for (int32_t i = 1; i < len; i++) {
    if (!p[i] || !is_utf8_continuation(p[i])) {
      return 0;  // Missing or invalid continuation byte
    }
  }

  if (is_utf8_continuation(p[len])) {
    return 0; // Next byte is also a continuation byte, invalid sequence
  }

  // Validate the encoded codepoint is in the valid range for its length
  // (rejects overlong encodings and invalid codepoints)
  uint32_t codepoint = 0;
  switch (len) {
    case 2:
      codepoint = (uint32_t)(((p[0] & 0x1F) << 6) | (p[1] & 0x3F));
      if (codepoint < 0x80) return 0;  // Overlong encoding
      break;
    case 3:
      codepoint = (uint32_t)(((p[0] & 0x0F) << 12) | ((p[1] & 0x3F) << 6) | (p[2] & 0x3F));
      if (codepoint < 0x800) return 0;  // Overlong encoding
      if (codepoint >= 0xD800 && codepoint <= 0xDFFF) return 0;  // Surrogate pairs
      break;
    case 4:
      codepoint = (uint32_t)(((p[0] & 0x07) << 18) | ((p[1] & 0x3F) << 12) | ((p[2] & 0x3F) << 6) | (p[3] & 0x3F));
      if (codepoint < 0x10000) return 0;  // Overlong encoding
      if (codepoint > 0x10FFFF) return 0;  // Beyond Unicode range
      break;
  }

  return len;
}

// This converts from a plain string to JSON string literal
// UTF-8 sequences are passed through unchanged; invalid/isolated high bytes are escaped.
cql_noexport void cg_encode_json_string_literal(CSTR str, charbuf *output) {
  const char quote = '"';
  const unsigned char *p = (const unsigned char *)str;

  bputc(output, quote);

  while (*p) {
    unsigned char c = *p;

    // Check for multi-byte UTF-8 sequence
    if (c >= 0x80) {
      int32_t seq_len = valid_utf8_sequence(p);
      if (seq_len > 1) {
        // Valid UTF-8 multi-byte sequence - pass through unchanged
        for (int32_t i = 0; i < seq_len; i++) {
          bputc(output, (char)p[i]);
        }
        p += seq_len;
        continue;
      }
      // Invalid/isolated high byte - fall through to escape it
    }

    // Use existing character encoder for ASCII and invalid bytes
    cg_encode_char_as_json_string_literal((char)c, output);
    p++;
  }
  bputc(output, quote);
}


// convert a single hex character to an integer
static uint32_t hex_to_int(char c) {
  uint32_t ch = (uint32_t)(unsigned char)c;
  if (ch >= '0' && ch <= '9')
    return ch - '0';

  if (ch >= 'a' && ch <= 'f')
     return ch - 'a' + 10;

  // this is all that's left
  Contract(ch >= 'A' && ch <= 'F');
  return ch - 'A' + 10;
}


// Accept only well-formed \xNN escapes and ignore malformed input so the caller
// can continue scanning safely; embedded nulls are rejected to avoid truncating
// the surrounding C string.
//
// For example, given a pointer to "x41", this will emit 'A' and advance
static void decode_hex_escape(CSTR *pstr, charbuf *output) {
  Contract(pstr);
  Contract(**pstr == 'x' || **pstr == 'X');
  CSTR p = *pstr;
  p++; // skip the 'x'

  // the escape sequence is not interpreted as hex if not well formed
  if (IsXDigit(p[0]) && IsXDigit(p[1])) {
    char ch = (char)(hex_to_int(p[0]) * 16 + hex_to_int(p[1]));

    // No embedded nulls, all the strings are null terminated so this will just screw everything up.
    if (ch != 0) {
      bputc(output, ch);
    }
    // note, the main loop will skip an additional character as a matter of course
    // so the second byte we do not pass over
    p++;

    // the input will be left on the 'x' if it wasn't well formed, which is the skipped as usual
    *pstr = p;
  }
}

// Decodes only canonical C string escapes under strict contracts: callers must
// pass a properly quoted literal, unknown escapes round-trip verbatim, and hex
// escapes reuse decode_hex_escape to avoid creating embedded nulls.
//
// For example, "\"Hello\\tWorld\\x21\"" produces the string: "Hello\tWorld!"
// That is the \t escape becomes an actual tab character and the \x21 becomes '!'
cql_noexport void cg_decode_c_string_literal(CSTR str, charbuf *output) {
  // don't call me with strings that are not properly "" delimited
  const char quote = '"';
  const char backslash = '\\';

  Contract(str[0] == quote);
  CSTR p = str + 1;

  for ( ;p[0]; p++) {
    if (p[0] == quote) {
      break;
    }

    if (p[0] != backslash) {
      bputc(output, p[0]);
      continue;
    }

    p++;
    switch (p[0]) {
      case 'a': bputc(output, '\a'); break;
      case 'b': bputc(output, '\b'); break;
      case 'f': bputc(output, '\f'); break;
      case 'n': bputc(output, '\n'); break;
      case 'r': bputc(output, '\r'); break;
      case 't': bputc(output, '\t'); break;
      case 'v': bputc(output, '\v'); break;
      case 'x': decode_hex_escape(&p, output); break;
      default : bputc(output, p[0]); break;
    }
  }

  // don't call me with strings that are not properly "" delimited
  Contract(p[0] == quote);
}

// When we need to execute SQL, we get the text of the SQL from the gen_ functions.
// Those functions return plaintext.  We need to quote that text so it can appear
// in a C string literal.  To do this we need to:
//  * put quotes around it
//  * do C string processing
//  * turn linefeeds into spaces (we break the string here for readability)
//    * or remove the unquoted linefeeds and indentation
cql_noexport void cg_pretty_quote_plaintext(CSTR str, charbuf *output, uint32_t flags) {
  Contract(str);

  const char squote = '\'';
  bool_t atStart = 1;
  bool_t inQuote = 0;
  bool_t multi_line = !!(flags & PRETTY_QUOTE_MULTI_LINE);
  bool_t for_json = !!(flags & PRETTY_QUOTE_JSON);

  bputc(output, '"');
  for (CSTR p = str; p[0]; p++) {
    // trim leading spaces down to one
    if (atStart && p[0] == ' ' && p[1] == ' ') {
       continue;
    }
    atStart = 0;
    // figure out if we're in quoted sql text, if we are then any newlines we see
    // are part of the string not part of our multi-line formatting.  They have to be escaped.
    if (!inQuote && p[0] == squote) {
      inQuote = 1;
      bprintf(output, "'");
    }
    else if (inQuote && p[0] == squote && p[1] == squote) {
      // escaped '' is escaped quote, stay in quoted mode
      bprintf(output, "''");
      // gobble the second quote since we just emitted it already
      // this way it has no way to fool us into leaving quoted mode (a previous bug)
      p++;
    }
    else if (inQuote && p[0] == squote) {
      inQuote = 0;
      bprintf(output, "'");
    }
    else if (!inQuote && p[0] == '\n') {
      if (multi_line) {
        // convert the newline to a space, break the string into multi-part literal
        bprintf(output, " \"\n  ");

        // use the embedded spaces to indent the string literal not to make the string fatter
        while (p[1] == ' ') {
          p++;
          bputc(output, ' ');
        }
        bputc(output, '"');
      }
      else {
        // emit the newline as a single space
        bputc(output, ' ');

        // eat any spaces that follow the newline
        while (p[1] == ' ') {
          p++;
        }
      }
    }
    else {
      if (for_json) {
        cg_encode_char_as_json_string_literal(p[0], output);
      }
      else {
        cg_encode_char_as_c_string_literal(p[0], output);
      }
    }
  }
  bputc(output, '"');
}

// This removes any "*/" and "/*" that happens in the buffer
// by converting them into "+/" and "/+" respectively.
//
// This is used for two purposes:
//
//   - To prevent prematurely ending a comment in an emitted
//     comment block.
//   - To prevent certain compiler under some compilation
//     flags from failing when they see an opening comment
//     marker inside a comment.
//
// You can only use this function on text that is going
// into a comment block.
cql_noexport void cg_remove_slash_star_and_star_slash(charbuf *_Nonnull b) {
  char *p = b->ptr;
  for (uint32_t i = 0; i < b->used - 2; i++) {
    if (p[i] == '*' && p[i+1] == '/') {
      p[i] = '+';
    }
    else if (p[i] == '/' && p[i+1] == '*') {
      p[i+1] = '+';
    }
  }
}

// Helper to case on string arguments to cql_compressed() and output
// readable multi-line strings when necessary.
cql_noexport void cg_pretty_quote_compressed_text(CSTR _Nonnull str, charbuf *_Nonnull output) {
  // In the case of an empty compressed string - cql_compressed("") we do not want
  // extra newlines
  if (strlen(str) == 0) {
    cg_pretty_quote_plaintext(str, output, PRETTY_QUOTE_C | PRETTY_QUOTE_MULTI_LINE);
    return;
  }

  // Otherwise, we want the SQL string to be new-line separated and indented for readability
  CHARBUF_OPEN(temp_output);
  bprintf(&temp_output, "\n  ");
  cg_pretty_quote_plaintext(str, &temp_output, PRETTY_QUOTE_C | PRETTY_QUOTE_MULTI_LINE);
  bindent(output, &temp_output, 6);
  bclear(&temp_output);
  bprintf(&temp_output, "\n      ");
  bprintf(output, "%s", temp_output.ptr);
  CHARBUF_CLOSE(temp_output);
}

// Preserve back-quoted identifiers while making them SQL-safe: allowed chars
// pass through, disallowed bytes become Xhh, and we synthesize the X_ prefix
// in-place to keep already-emitted text contiguous without extra buffers.
//
// For instance "X_helloX20worldX21" becomes "`hello world!`"
cql_noexport void cg_encode_qstr(charbuf *_Nonnull output, CSTR _Nonnull qstr) {
  Contract(qstr);
  Contract(qstr[0] == '`');
  uint32_t len = (uint32_t)strlen(qstr);
  Contract(len >= 3);  // `a` is the smallest legal string
  Contract(qstr[len-1] == '`');
  uint32_t used = output->used;

  bool_t used_hex = false;
  len--;
  uint32_t i;
  for (i = 1; i < len; i++) {
    uint8_t ch = (uint8_t)qstr[i];
    if (
      (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z' && ch != 'X') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_') {
        bputc(output, qstr[i]);
        continue;
    }

    if (qstr[i] == '`') {
      // the string is known to be well formed!
      // skip the second ` of the series
      Contract(qstr[i+1] == '`');
      i++;
    }

    bputc(output, 'X');
    emit_hex_digit(ch >> 4, output);
    emit_hex_digit(ch & 0xf, output);
    used_hex = true;
  }

  if (used_hex) {
    // place holders to make space
    bputc(output, '$');
    bputc(output, '$');
    // shift the string up two characters
    memmove(output->ptr + used + 1, output->ptr + used - 1, output->used - used - 2);
    // add the X_ prefix
    output->ptr[used-1] = 'X';
    output->ptr[used] = '_';
  }
}


// Rehydrates identifiers produced by cg_encode_qstr: if no X_ prefix is present
// we simply rewrap, otherwise we decode hex escapes and reinsert back ticks so
// previously escaped back-quote runs are preserved.
//
// For example, "X_helloX20worldX21" becomes "`hello world!`"
cql_noexport void cg_decode_qstr(charbuf *_Nonnull output, CSTR _Nonnull qstr) {
  Contract(qstr);

  // The string was quoted but didn't require escapes, just put the original back-quotes back
  if (qstr[0] != 'X' || qstr[1] != '_') {
    bprintf(output, "`%s`", qstr);
    return;
  }

  bputc(output, '`');
  qstr += 2;
  for (; *qstr; qstr++) {
    if (*qstr != 'X') {
      bputc(output, *qstr);
    }
    else {
      decode_hex_escape(&qstr, output);
      if (output->ptr[output->used - 2] == '`') {
        bputc(output, '`');
      }
    }
  }
  bputc(output, '`');
}

// Returns the bare identifier without back-quote wrappers and with hex escapes decoded.
//
// For example, "X_helloX20worldX21" becomes "hello world!
cql_noexport void cg_unquote_encoded_qstr(charbuf *_Nonnull output, CSTR _Nonnull qstr) {
  Contract(qstr);

  // The string was quoted but didn't require escapes, just put the original
  // back-quotes back
  if (qstr[0] != 'X' || qstr[1] != '_') {
    bprintf(output, "%s", qstr);
    return;
  }

  qstr += 2;
  for (; *qstr; qstr++) {
    if (*qstr != 'X') {
      bputc(output, *qstr);
    }
    else {
      decode_hex_escape(&qstr, output);
    }
  }
}
