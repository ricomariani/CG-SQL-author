#!/usr/bin/env python3

# Copyright (c) Joris Garonian and Rico Mariani
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# Focused tests for the two encoding contexts used when generating a virtual
# table declaration.  SQL identifiers are quoted first; the resulting SQL is
# later embedded in C and therefore requires an independent C string encoding.

import cqlsqlite3extension


def main():
    # SQLite identifiers use doubled double quotes.  The right bracket is
    # intentionally present to ensure the old bracket-quoting assumption is not
    # reintroduced.
    assert cqlsqlite3extension.quote_sql_identifier('odd]"name') == '"odd]""name"'

    # The C encoder must handle quotes, backslashes, line controls, and question
    # marks.  The final pair verifies trigraph prevention as well as ordinary
    # slash preservation.
    assert cqlsqlite3extension.c_string_literal('a"b\\c\n??/d') == (
        '"a\\"b\\\\c\\n\\?\\?/d"'
    )


if __name__ == "__main__":
    main()
