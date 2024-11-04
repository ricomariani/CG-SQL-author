#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# ###################################################################################
# tree_sitter.py:
# ---------------
#
# Generates tree-sitter grammar for the CQL language. This can be used to drive
# good quality syntax highlighting and code folding in editors that support
# tree-sitter.  The script reads the cql_grammar.txt file and generates the
# tree-sitter grammar file. The script also handles the following:
#
# Optional rules: If a rule is originally optional, it adds the "optional()"
#   function to the rule's usages. Tree sitter does not allow rules with empty
#   sequences.
#
# Apply functions: Some rules have conflicts, therefore we need to define the
#   precedence priority.  The script can wrap the rule in a precedence function
#   to resolve the conflict.  In fact any kind of wrapping can be applied here.
#
# Line breaks: Some rules are big and have multiple choices. The script adds a
#   line break to the choices to make it more readable.
#
# Token grammar: Terminals are automatically detected and added to the grammar.
# 
# Inline rules: Some rules are problematic to the cql tree-sitter grammar. The
#   script replaces them wherever they're used with their values.
#
# Deleted productions: These are rules that are present in cql_grammar.txt but
#   are helpfully defined such as `quoted identifier` and `ELSE_IF`. The script
#   deletes them from the tree-sitter grammar.
#
# Rule renames: Some rules have readable names in cql_grammar.txt but are not
#   suitable for tree-sitter. These rules are renamed to a more suitable name,
#   such as `integer-literal` to `INT_LIT`.
#
# Boot rules: Some rules are not defined in cql_grammar.txt. The script manually
#   defines them in the tree-sitter grammar.  This is where the `INT_LIT`,
#   `LONG_LIT`, `REAL_LIT`, `BLOB_LIT`, `C_STR_LIT`, `STR_LIT`, `ID`, `ID_BANG`,
#   `QID`, `include_stmt`, `comment`, and so forth appear.
#
# Extras: The script adds the `extras` and `conflicts` sections to the
#   tree-sitter grammar to get whitespace and comments in the right places in
#   the grammar.
#
# #####################################################################################

import sys
import datetime
import re


NULL_PATTERN = re.compile(r"/\*\s*nil\s*\*/")
SEQUENCE_PATTERN = re.compile(r"\"[^\"]+\"|'.?'|[\w\-\_@]+")
WORD_PATTERN = re.compile(r"[\w\-\_@]+")
STRING_PATTERN = re.compile(r"\"[^\"]+\"")
RULE_PATTERN = re.compile(r"(.*)\s*::=\s*(.*)")
CHOICE_PATTERN = re.compile(r"\s+\|\s+")
SPACE_PATTERN = re.compile(r"\s+")
QUOTE_WORD_PATTERN = re.compile(r"'[^']+'")
OPERATOR_PATTERN = re.compile(r"\"[+-=:~/*,<>]+\"")

LINE_BREAK_RULES = [
  "any_literal",
  "any_stmt",
  "basic_expr",
  "col_attrs",
  "create_index_stmt",
  "create_proc_stmt",
  "create_table_stmt",
  "create_view_stmt",
  "create_virtual_table_stmt",
  "cte_table",
  "data_type_any",
  "data_type_numeric",
  "data_type_with_options",
  "declare_forward_read_cursor_stmt",
  "declare_func_stmt",
  "declare_proc_stmt",
  "declare_select_func_stmt",
  "declare_value_cursor",
  "enforcement_options",
  "explain_target",
  "expr",
  "fetch_values_stmt",
  "fk_def",
  "fk_on_options",
  "from_shape",
  "insert_stmt",
  "insert_stmt_type",
  "math_expr",
  "misc_attr",
  "name",
  "op_stmt",
  "pk_def",
  "raise_expr",
  "rollback_trans_stmt",
  "schema_ad_hoc_migration_stmt",
  "select_core",
  "select_core_list",
  "simple_call",
  "table_or_subquery",
  "trycatch_stmt",
  "unq_def",
  "update_cursor_stmt",
  "update_stmt",
  "upsert_stmt",
  "version_attrs_opt_recreate",
]

# Some of the rules have conflicts therefore we need to define the precedent priority.
APPLY_FUNC_LIST = {
    "fk_target_options": "prec.left({})",
    "join_target": "prec.left({})",
    "elseif_list": "prec.left({})",
    "cte_decl": "prec.left(1, {})",
    "loose_name": "prec.left(100, {})",
    "basic_expr": "prec.left(1, {})",
    "math_expr": "prec.left(1, {})",
    "expr": "prec.left(1, {})",
}

# These rules have invalid names for tree-sitter. We're going to rename them.
# We use this mechanism (that a rename is in flight) to also avoid
# automatic creation of terminal tokens.  Two cases marked below.
RULE_RENAMES = {
    "integer-literal": "INT_LIT",
    "long-literal": "LONG_LIT",
    "real-literal": "REAL_LIT",
    "sql-blob-literal": "BLOB_LIT",
    "c-string-literal": "C_STR_LIT",
    "sql-string-literal": "STR_LIT",
    "ID!": "ID_BANG",
    "`quoted_identifier`": "QID",
    "ID": "ID",  # prevents CI("id) rule
    "ELSE_IF" : "ELSE_IF" # prevents seq(CI("ELSE"), CI("IF"))
}

BOOT_RULES = """
    program: $ => optional($.stmt_list),

    INT_LIT: $ => choice(/[0-9]+/, /0x[0-9a-fA-F]+/),
    LONG_LIT: $ => choice(/[0-9]+L/, /0x[0-9a-fA-F]+L/),
    REAL_LIT: $ => /([0-9]+\.[0-9]*|\.[0-9]+)((E|e)(\+|\-)?[0-9]+)?/,
    BLOB_LIT: $ => /[xX]'([0-9a-fA-F][0-9a-fA-F])*'/,
    C_STR_LIT: $ => /"(\\.|[^"\\n])*"/,
    STR_LIT: $ => /'(\\.|''|[^'])*'/,
    ID: $ => /[_A-Za-z][A-Za-z0-9_]*/,
    ID_BANG: $ => /[_A-Za-z][A-Za-z0-9_]*[!]/,
    QID: $ => /`(``|[^`\\n])*`/,

    /* no newline between ELSE and IF */
    ELSE_IF: $ => /[Ee][Ll][sS][eE][ \\t]*[Ii][Ff][ \\t\\n]/,

    include_stmt: $ => seq(CI('@include'), $.C_STR_LIT),

    comment: $ => token(choice(
       seq('--', /(\\\\(.|\\r?\\n)|[^\\\\\\n])*/),
       seq('/*', /[^*]*\*+([^/*][^*]*\*+)*/, '/'))),

    non_expr_macro_ref: $ => choice(
      $.stmt_list_macro_ref,
      $.cte_tables_macro_ref,
      $.select_core_macro_ref,
      $.select_expr_macro_ref,
      $.query_parts_macro_ref),

    expr_macro_ref: $ => prec.left(1,choice(
      seq($.ID_BANG),
      seq($.ID_BANG, '(', optional($.opt_macro_args), ')'),
      seq($.basic_expr, ':', $.ID_BANG, '(', optional($.opt_macro_args), ')'),
      seq($.basic_expr, ':', $.ID_BANG))),

    macro_ref: $ => choice(seq($.ID_BANG), seq($.ID_BANG, '(', optional($.opt_macro_args), ')')),

    query_parts_macro_ref: $ => prec(1, $.macro_ref),
    cte_tables_macro_ref: $ => prec(2, $.macro_ref),
    select_core_macro_ref: $ => prec(3, $.macro_ref),
    select_expr_macro_ref: $ => prec(4, $.macro_ref),
    stmt_list_macro_ref: $ => prec(5, $.macro_ref),

    AT_IFDEF: $ => CI('@ifdef'),
    AT_IFNDEF: $ => CI('@ifndef'),
    AT_ELSE: $ => CI('@else'),
    AT_ENDIF: $ => CI('@endif'),

    ifdef: $ => seq($.AT_IFDEF, $.ID, $.stmt_list, optional(seq($.AT_ELSE, $.stmt_list)), $.AT_ENDIF),
    ifndef: $ => seq($.AT_IFNDEF, $.ID, $.stmt_list, optional(seq($.AT_ELSE, $.stmt_list)), $.AT_ENDIF),

    pre_proc: $ => choice($.ifdef, $.ifndef),

    stmt_list: $ => repeat1(choice($.stmt, $.include_stmt, $.pre_proc, $.comment)),

    /* Manually define the if_stmt rule because if not we're going to have parsing
     * issues with "opt_elseif_list" and "opt_else" rule. Providing a priority
     * doesn't suffice to resolve the conflict.
     */

    if_stmt: $ => seq($.IF, $.expr, $.THEN,
        optional($.stmt_list),
        optional(repeat1($.elseif_item)),
        optional($.opt_else),
        $.END, optional($.IF)),
"""

# These are problematic rules to the cql tree-sitter grammar. We're just going
# to replace them wherever they're used with their values.
INLINE_RULES = {
    # The presence of this node break tree-sitter. It was added to
    # 'create_table_stmt' for the sole purpose of grabbing documentation
    "create_table_prefix_opt_temp",
}

DELETED_PRODUCTIONS = {
    # These will get emitted some other kind of way, like in the BOOT section
    "@INCLUDE_quoted-filename",
    "ELSE_IF"
    "cte_tables_macro_ref",
    "end_of_included_file",
    "expr_macro_ref",
    "if_stmt",
    "include_section",
    "include_stmts",
    "non_expr_macro_ref",
    "opt_distinct",
    "opt_stmt_list",
    "program",
    "query_parts_macro_ref",
    "select_core_macro_ref",
    "select_expr_macro_ref",
    "stmt_list",
    "stmt_list_macro_ref",
    "top_level_stmts",
    "`quoted_identifier`"
}

input_filename = sys.argv[1] if len(sys.argv) > 1 else "cql_grammar.txt"
grammar = {}
tokens = {}

rule_defs = {}
sorted_rule_names = []
optional_rules = set()
rules_name_visited = set()


def add_ts_rule(name, ts_rule):
    grammar[name] = ts_rule

def get_rule_ref(token):
    if token in RULE_RENAMES:
        return "$.{}".format(RULE_RENAMES[token])

    if QUOTE_WORD_PATTERN.match(token):
        return token

    if OPERATOR_PATTERN.match(token):
        return token

    if STRING_PATTERN.match(token):
        tk = token.strip('"')
        if WORD_PATTERN.match(tk):
            if tk in RULE_RENAMES:
                return "$.{}".format(RULE_RENAMES[tk])
            name = tk.replace("@", "AT_")
            if name not in tokens:
                tokens[name] = "{}: $ => CI('{}')".format(name, tk.lower())
            return "$.{}".format(name)
        else:
            return token

    if token == "opt_stmt_list":
        return "optional($.stmt_list)"

    if token == "opt_distinct":
        return "optional($.DISTINCT)"

    return (
        "optional($.{})".format(token)
        if token in optional_rules
        else "$.{}".format(token)
    )


def add_sub_sequence(tokens):
    name = "_".join(tokens)
    if name not in rules_name_visited:
        values = ["CI('{}')".format(item.lower()) for item in tokens]
        ts_rule = "$ => prec.left(1, seq({}))".format(", ".join(values))
        add_ts_rule(name, ts_rule)
        rules_name_visited.add(name)
    return name


# Process a sub-sequence within a sequence. they are a group of words within a
# string e.g., "IS NOT TRUE"
def get_sub_sequence(seq):
    tokens = SPACE_PATTERN.split(seq.strip('"'))
    name = add_sub_sequence(tokens)
    return get_rule_ref(name)

# Process a sequence in a rule.
# e.g., IS_NOT_TRUE: "is" "not" "true"
def get_sequence(sequence):
    tokens_list = []
    for tk in sequence:
        tk = tk.strip()
        if len(tk) > 0:
            if SPACE_PATTERN.search(tk):
                tokens_list.append(get_sub_sequence(tk))
            elif STRING_PATTERN.match(tk):
                tokens_list.append(get_rule_ref(tk))
            else:
                tokens_list.append(get_rule_ref(tk))
    return tokens_list


with open(input_filename) as fp:
    for line in RULE_PATTERN.finditer(fp.read()):
        assert line.lastindex == 2
        name = line.group(1).strip()
        rule = line.group(2)
        choices = []
        for choice in CHOICE_PATTERN.split(rule):
            seq = []
            if NULL_PATTERN.match(choice):
                optional_rules.add(name)
            else:
                seq = [r.strip() for r in re.findall(SEQUENCE_PATTERN, choice)]
            if len(seq) > 0:
                # the rule is not optional
                choices.append(seq)
        rule_defs[name] = choices
        sorted_rule_names.append(name)

# Inline where needed to avoid conflicts
for _, rule in rule_defs.items():
    cpy_rule = []
    for i, seq in enumerate(rule):
        for j, item in enumerate(seq):
            if type(item) is str and item in INLINE_RULES:
                rule[i] = seq[0 : max(j - 1, 0)] + rule_defs[item][0] + seq[j + 1 :]

# Delete the inline rules
for name in INLINE_RULES:
    del rule_defs[name]
    rules_name_visited.add(name)

for name in sorted_rule_names:
    if name in rules_name_visited:
        continue

    rules_name_visited.add(name)
    choices = []

    for rule in rule_defs[name]:
        seq = get_sequence(rule)
        size = len(seq)
        if size == 0:
            # An empty sequence in the rule indicates that the rule is optional.
            # We dont need to do anything here, we just move on. later it's
            # used to add the "optional()" function to optional rule's definition.
            continue
        elif size == 1:
            choices.append(seq[0])
        else:
            choices.append("seq({})".format(", ".join(seq)))

    if len(choices) == 1:
        rule_str = choices[0]
    else:
        if name in LINE_BREAK_RULES:
          rule_str = "choice({})".format(",\n      ".join(choices))
        else:
          rule_str = "choice({})".format(", ".join(choices))

    if name in APPLY_FUNC_LIST:
        rule_str = APPLY_FUNC_LIST[name].format(rule_str)

    add_ts_rule(name, "$ => {}".format(rule_str))

for r in RULE_RENAMES.values():
  DELETED_PRODUCTIONS.add(r)

grammar_text = ",\n    ".join(
    ["{}: {}".format(ts, grammar[ts]) for ts in grammar.keys() if ts not in DELETED_PRODUCTIONS]
    + list(tokens.values())
)

print(
    "/**\n"
    " * Copyright (c) Meta Platforms, Inc. and affiliates.\n"
    " *\n"
    " * This source code is licensed under the MIT license found in the\n"
    " * LICENSE file in the root directory of this source tree.\n"
    " */\n\n"
)
print(
    "const PREC = {\n"
    "};\n\n"
    "module.exports = grammar({\n"
    "  name: 'cql',\n"
    "  extras: $ => [\n"
    "     /\\s|\\\\\\r?\\n/,\n"
    "     $.comment\n"
    "  ],\n"
    "  conflicts: $ => [\n"
    "     [$.fk_options],\n"
    "  ],\n"
    "  word: $ => $.ID,\n"
    "  rules: {", end = ""
)
print("{}    {}".format(BOOT_RULES, grammar_text))
print(
    "  }\n"
    "});\n\n"
    "// make string case insensitive\n"
    "function CI (keyword) {\n"
    "  return new RegExp(keyword\n"
    "     .split('')\n"
    "     .map(letter => `[${letter}${letter.toUpperCase()}]`)\n"
    "     .join('')\n"
    "  )\n"
    "}\n"
)
