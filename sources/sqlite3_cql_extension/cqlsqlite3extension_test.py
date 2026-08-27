#!/usr/bin/env python3

# Copyright (c) Joris Garonian and Rico Mariani
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import cqlsqlite3extension


def main():
    assert cqlsqlite3extension.quote_sql_identifier('odd]"name') == '"odd]""name"'
    assert cqlsqlite3extension.c_string_literal('a"b\\c\n??/d') == (
        '"a\\"b\\\\c\\n\\?\\?/d"'
    )


if __name__ == "__main__":
    main()
