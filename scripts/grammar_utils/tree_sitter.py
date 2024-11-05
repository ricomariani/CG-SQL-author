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
# Fixed rules: Some rules are not defined in cql_grammar.txt. The script manually
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


# We emit /* nil */ in the grammar to indicate an empty match.  This signals optional rules.
NULL_PATTERN = re.compile(r"/\*\s*nil\s*\*/")

# The valid items in a non-terminal rules.  Double quoted strings, characters, and names.
SEQUENCE_PATTERN = re.compile(r"\"[^\"]+\"|'.?'|[\w\-\_@]+")

# A single word pattern including special characters "-", "_", and "@".
WORD_PATTERN = re.compile(r"[\w\-\_@]+")

# A string pattern.  Note that there are no escapes. We can get away with no
# escapes because we know that the grammar.txt file never contains them.
STRING_PATTERN = re.compile(r"\"[^\"]+\"")

# The rule pattern.  This is the rule name followed by the rule definition.
# The rule definition is a series of choices separated by "|".  The production
# uses the ::= separator common in W3C grammars.
RULE_PATTERN = re.compile(r"(.*)\s*::=\s*(.*)")

# This helps us to identify that there is an choice in the rule.
CHOICE_PATTERN = re.compile(r"\s+\|\s+")

# The space pattern.  This is used to split the a "MULTI WORD" token into its parts.
SPACE_PATTERN = re.compile(r"\s+")

# Long single quoted string with no escapes. We can get away with no escapes
# because we know that the grammar.txt file never contains them.
SINGLE_QUOTE_WORD_PATTERN = re.compile(r"'[^']+'")

# If we find a quoted string of just operator characters that means it's a long
# operator we shouldn't make a CI(x) production for it.  These are just the
# characters that could make a "long" operator like "<<", "<<=" or "->>".
OPERATOR_PATTERN = re.compile(r"\"[!+-=:~/*<>]+\"")

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
    "integer-literal": "$.INT_LIT",
    "long-literal": "$.LONG_LIT",
    "real-literal": "$.REAL_LIT",
    "sql-blob-literal": "$.BLOB_LIT",
    "c-string-literal": "$.C_STR_LIT",
    "sql-string-literal": "$.STR_LIT",
    "ID!": "$.ID_BANG",
    "`quoted_identifier`": "$.QID",

    # prevents CI("id) rule
    "ID": "$.ID",

    # prevents seq(CI("ELSE"), CI("IF"))
    "\"ELSE IF\"" : "$.ELSE_IF",

    # We special case these common references to something more direct
    # otherwise we would have a ton of optional(opt_stmt_list)
    # We can do these ones because they are direct aliases the 
    # opt_ rule adds no value.
    "opt_stmt_list" : "optional($.stmt_list)",
    "opt_distinct" : "optional($.DISTINCT)",
    "opt_version_attrs" : "optional($.version_attrs)",
    "opt_conflict_clause" : "optional($.conflict_clause)",
    "opt_fk_options" : "optional($.fk_options)",
    "opt_sql_name" : "optional($.sql_name)",
    "opt_name_list" : "optional($.name_list)",
    "opt_sql_name_list" : "optional($.sql_name_list)",
    "opt_expr_list" : "optional($.expr_list)",
    "opt_select_window" : "optional($.select_window)",
    "opt_as_alias" : "optional($.as_alias)",
    "opt_join_cond" : "optional($.join_cond)",
    "opt_elseif_list" : "optional($.elseif_list)",
    "opt_macro_args" : "optional($.macro_args)",
    "opt_macro_formals" : "optional($.macro_formals)",
}

FIXED_RULES = """
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
    "`quoted_identifier`"
    "cte_tables_macro_ref",
    "end_of_included_file",
    "expr_macro_ref",
    "if_stmt",
    "include_section",
    "include_stmts",
    "non_expr_macro_ref",
    "program",
    "query_parts_macro_ref",
    "select_core_macro_ref",
    "select_expr_macro_ref",
    "stmt_list",
    "stmt_list_macro_ref",
    "top_level_stmts",

    # These are just aliases for the non-optional rules.  We don't need them.
    # Since we always emit something like optional($.stmt_list) rather than
    # $.opt_stmt_list, or even worse optional($.opt_stmt_list).

    "opt_as_alias",
    "opt_conflict_clause",
    "opt_distinct",
    "opt_elseif_list",
    "opt_expr_list",
    "opt_fk_options",
    "opt_join_cond",
    "opt_macro_args",
    "opt_macro_formals",
    "opt_name_list",
    "opt_select_window",
    "opt_sql_name",
    "opt_sql_name_list",
    "opt_stmt_list",
    "opt_version_attrs",
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
        return RULE_RENAMES[token]

    # Returning the token here turns it into lexeme in the tree-sitter grammar
    if SINGLE_QUOTE_WORD_PATTERN.match(token):
        return token

    # Returning the token here turns it into lexeme in the tree-sitter grammar
    if OPERATOR_PATTERN.match(token):
        return token

    # This bit exists so that tokens like "@OP" in the grammar are turned into
    # "AT_OP: $ => CI('@OP')" in the tree-sitter grammar. This takes terminals
    # in the grammar and turns them into lexemes tree-sitter can use. Recall
    # that in tree-sitter there is no lexer.
    if STRING_PATTERN.match(token):
        # We strip the quotes from the token and then see if what is left
        # looks like a word, this is what the normal terminals look like.
        # We want those to be case-insensitive.  Anything else can stay
        # as a literal lexeme.
        tk = token.strip('"')
        if not WORD_PATTERN.match(tk):
            return token

        # The terminal might have a rename.  If so we use that.
        if tk in RULE_RENAMES:
            return RULE_RENAMES[tk]

        # Add the token if we need it, correct the @ to AT_ for the name.
        name = tk.replace("@", "AT_")
        if name not in tokens:
            tokens[name] = "{}: $ => CI('{}')".format(name, tk.lower())

        # Return a reference to the (possibly new) synthesized token.
        return "$.{}".format(name)

    # If the token is optional, we add "optional()" to the rule's references.
    # Tree sitter does not allow rule definitions with empty sequences, so we
    # need to add the "optional()" function to optional rule's references.
    if token in optional_rules:
        return "optional($.{})".format(token)
    else:
        return  "$.{}".format(token)

# Process a terminal with spaces in it like "IS NOT TRUE" and turn that
# into a rule that is a sequence of the parts.  This gives us multi-word
# terminals that are case insensitive.
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
            if tk in RULE_RENAMES:
                # for renames we have the answer on a silver platter
                tokens_list.append(get_rule_ref(tk))
            elif SPACE_PATTERN.search(tk):
                # if space in the name emit a broken up token
                # e.g. "IS NOT TRUE" -> IS_NOT_TRUE: "is" "not" "true"
                tokens_list.append(get_sub_sequence(tk))
            else:
                # otherwise just emit a normal token reference
                # this handles string tokens becoming lexemes
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
            # A sequence of length 1 does not require a seq() wrapper.
            choices.append(seq[0])
        else:
            choices.append("seq({})".format(", ".join(seq)))

    if len(choices) == 1:
        rule_str = choices[0]
    else:
        rule_str = "choice(\n      {})".format(",\n      ".join(choices))

    if name in APPLY_FUNC_LIST:
        rule_str = APPLY_FUNC_LIST[name].format(rule_str)

    add_ts_rule(name, "$ => {}".format(rule_str))

for r in RULE_RENAMES.values():
  DELETED_PRODUCTIONS.add(r)

grammar_text = ",\n\n    ".join(
    ["{}: {}".format(ts, grammar[ts]) for ts in grammar.keys() if ts not in DELETED_PRODUCTIONS]
    + list(tokens.values())
)

print("""/**
 *
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

const PREC = {
};

module.exports = grammar({
  name: 'cql',
  extras: $ => [
     /\\s|\\r?\\n/,
     $.comment
  ],
  conflicts: $ => [
     [$.fk_options],
  ],
  word: $ => $.ID,
  rules: {""", end="")

print("{}    {}".format(FIXED_RULES, grammar_text))

print("""
  }
});

// The all important "make case-insensitive token" function
// This is used on virtually every terminal symbol in the grammar.
function CI (keyword) {
  return new RegExp(keyword
     .split('')
     .map(letter => `[${letter}${letter.toUpperCase()}]`)
     .join('')
  )
}""")