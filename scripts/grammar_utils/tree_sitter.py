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
#   `LONG_LIT`, `REAL_LIT`, `BLOB_LIT`, `C_STR_LIT`, `STR_LIT`, `ID`
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
    "`quoted_identifier`": "$.QID",

    # prevents CI("id) rule
    "ID": "$.ID",

    # prevents seq(CI("ELSE"), CI("IF"))
    "\"ELSE IF\"": "$.ELSE_IF",

    # prevents `quoted_identifier` token
    "\"`quoted identifier`\"": "$.QID",

    # We special case these common references to something more direct
    # otherwise we would have a ton of optional(opt_stmt_list)
    # We can do these ones because they are direct aliases the
    # opt_ rule adds no value.
    "opt_stmt_list": "optional($.stmt_list)",
    "opt_distinct": "optional($.DISTINCT)",
    "opt_version_attrs": "optional($.version_attrs)",
    "opt_conflict_clause": "optional($.conflict_clause)",
    "opt_fk_options": "optional($.fk_options)",
    "opt_sql_name": "optional($.sql_name)",
    "opt_name_list": "optional($.name_list)",
    "opt_sql_name_list": "optional($.sql_name_list)",
    "opt_expr_list": "optional($.expr_list)",
    "opt_as_alias": "optional($.as_alias)",
    "opt_join_cond": "optional($.join_cond)",
    "opt_elseif_list": "optional($.elseif_list)",
    "opt_macro_args": "optional($.macro_args)",
    "opt_macro_formals": "optional($.macro_formals)",
    "if_ending" : "$.END, optional($.IF)",
}

FIXED_RULES = """
    program: $ => optional($.stmt_list),

    INT_LIT: $ => choice(/[0-9]+/, /0x[0-9a-fA-F]+/),
    LONG_LIT: $ => choice(/[0-9]+L/, /0x[0-9a-fA-F]+L/),
    REAL_LIT: $ => /([0-9]+\.[0-9]*|\.[0-9]+)((E|e)(\+|\-)?[0-9]+)?/,
    BLOB_LIT: $ => /[xX]'([0-9a-fA-F][0-9a-fA-F])*'/,
    C_STR_LIT: $ => /"(\\\\.|[^"\\n])*"/,
    STR_LIT: $ => /'(''|[^'])*'/,
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
      seq($.name, '!'),
      seq($.name, '!', '(', optional($.macro_args), ')'),
      seq($.basic_expr, ':', $.name, '!', '(', optional($.macro_args), ')'),
      seq($.basic_expr, ':', $.name, '!'))),

    macro_ref: $ => choice(seq($.name, '!'), seq($.name, '!', '(', optional($.macro_args), ')')),

    query_parts_macro_ref: $ => prec(1, $.macro_ref),
    cte_tables_macro_ref: $ => prec(2, $.macro_ref),
    select_core_macro_ref: $ => prec(3, $.macro_ref),
    select_expr_macro_ref: $ => prec(4, $.macro_ref),
    stmt_list_macro_ref: $ => prec(5, $.macro_ref),

    stmt_list: $ => repeat1(choice($.stmt, $.include_stmt, $.comment)),
"""

# These are problematic rules to the cql tree-sitter grammar. We're just going
# to replace them wherever they're used with their values.
INLINE_RULES = {
    # The presence of this node break tree-sitter. It was added to
    # 'create_table_stmt' for the sole purpose of grabbing documentation
    "create_table_prefix_opt_temp",
    "ifdef",
    "ifndef",
    "elsedef",
    "endif",
}

DELETED_PRODUCTIONS = {
    # These will get emitted some other kind of way, like in the FIXED_RULES
    # section, or the tokens section.
    "@INCLUDE_quoted-filename",
    "ELSE_IF",
    "ID!",
    "`quoted_identifier`",
    "cte_tables_macro_ref",
    "end_of_included_file",
    "expr_macro_ref",
    # "if_stmt",
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
}

# if we renamed all references to the rule then we can't possibly still
# need to emit it, it's a orphan for sure. No need to list them all twice
# so add all those to the DELETED_PRODUCTIONS list.
for rule in RULE_RENAMES:
    DELETED_PRODUCTIONS.add(rule)

input_filename = sys.argv[1] if len(sys.argv) > 1 else "cql_grammar.txt"
grammar = {}
synthesized_tokens = {}

# The rule_defs dictionary is a map of rule names to a list of choices. Each
# choice is a list of tokens.  The tokens are either terminals or non-terminals.
# These are as the rules exist in the grammar file, at least at first. We will
# transform with renames and inlining and then ignore anything orphaned.
rule_defs = {}

# The sorted_rule_names list is the order in which the rules were seen in the
# grammar file. This is important because we want to emit the non-terminals in
# the order they were seen.
sorted_rule_names = []

# We need to keep track of the optional rules so we can add the "optional()"
# to their references.
optional_rules = set()

# We need to keep track of the rules we have visited so we do not emit them
# more than once.  This is important because sorted_rule_names might have
# duplicates and we want to skip visiting of rules we inlined.  We also
# want to skip rules that we have expanded into new non-terminals like
# multi-word tokens "IS NOT TRUE" -> IS_NOT_TRUE.
rules_visited = set()

# Store the indicated rule in the result grammar
def add_ts_rule(name, ts_rule):
    grammar[name] = ts_rule

# This converts a token, terminal or non-terminal, into a reference in the grammar
# So like "ID" becomes "$.ID" and "integer-literal" becomes "$.INT_LIT".  It has
# to handle rules with optional references, and it has to handle multi-word tokens.
# It can even create a new token if it needs to (like "IS NOT TRUE" -> IS_NOT_TRUE).
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
        if name not in synthesized_tokens:
            synthesized_tokens[name] = "{}: $ => CI('{}')".format(name, tk.lower())

        # Return a reference to the (possibly new) synthesized token.
        return "$.{}".format(name)

    # If the token is optional, we add "optional()" to the rule's references.
    # Tree sitter does not allow rule definitions with empty sequences, so we
    # need to add the "optional()" function to optional rule's references.
    if token in optional_rules:
        return "optional($.{})".format(token)
    else:
        return "$.{}".format(token)


# Tokens has the parts of a terminal with spaces in it like "IS NOT TRUE" so
# ["IS", "NOT", "TRUE"]. Here we convert those parts into a single token by
# joining them with "_".  So we get "IS_NOT_TRUE". We then add the token to the
# grammar and turn it into a rule that is a sequence of the parts.  This gives
# us multi-word terminals that are case insensitive.
def add_sub_sequence(seq):
    name = "_".join(seq)
    if name not in rules_visited:
        # Formulate the rule for the multi-word token
        values = ["CI('{}')".format(item.lower()) for item in seq]
        ts_rule = "{}: $ => prec.left(1, seq({}))".format(name, ", ".join(values))
        synthesized_tokens[name] = ts_rule

        # We do not want to do this particular split again.
        rules_visited.add(name)

    # Return the name of the new or existing rule for this multi-word token.
    return name

# Process a sub-sequence within a sequence. they are a group of words within a
# string e.g., "IS NOT TRUE"
def get_sub_sequence(token):
    seq = SPACE_PATTERN.split(token.strip('"'))
    name = add_sub_sequence(seq)
    return get_rule_ref(name)

# Process a sequence in a rule.
# We process each token in the rule converting it into a reference in the grammar.
# This is where we rename tokens as needed and split multi-word tokens into parts.
def get_sequence(sequence):
    tokens_list = []
    for tk in sequence:
        tk = tk.strip()
        if len(tk) > 0:
            if tk in RULE_RENAMES:
                # for renames we have the answer on a silver platter
                # get_rule_ref will do the actual rename
                tokens_list.append(get_rule_ref(tk))
            elif SPACE_PATTERN.search(tk):
                # if space in the name emit a broken up token
                # e.g. "IS NOT TRUE" -> IS_NOT_TRUE: "is" "not" "true"
                tokens_list.append(get_sub_sequence(tk))
            else:
                # otherwise just emit a normal token reference
                # this handles string tokens becoming lexemes
                # in the case where they are not multi-word
                # (hence get_sub_sequence is not required)
                tokens_list.append(get_rule_ref(tk))

    return tokens_list

# Read each rule from the grammar text file into the rule_defs dictionary.
# The rule_defs dictionary is a map of rule names to a list of choices.
# Each choice is a list of tokens.  The tokens are either terminals or non-terminals.
def read_rule_defs(fp):
    for line in RULE_PATTERN.finditer(fp.read()):
        assert line.lastindex == 2
        name = line.group(1).strip()
        rule = line.group(2)

        # We're ready to compute the choices for this rule.  In the grammar
        # file the choices are separated by "|".  We split the rule into
        # choices and then split the choices into terminals/non-terminals.
        choices = []
        for choice in CHOICE_PATTERN.split(rule):
            if NULL_PATTERN.match(choice):
                seq = []
            else:
                seq = [r.strip() for r in re.findall(SEQUENCE_PATTERN, choice)]

            # if there was a sequence add it to the choices, if this sequence
            # is empty it means the rule is optional (i.e. it can match nothing).
            # This could happen with an empty sequence or with the nil pattern.
            if len(seq) > 0:
                choices.append(seq)
            else:
                optional_rules.add(name)

        # We can now store these choices and record the order we found them.
        rule_defs[name] = choices
        sorted_rule_names.append(name)


# The indicated sequence has been found to have inlines, we process them
# all in one go now.  We have to do this because the procedure we follow
# here builds an entirely result, it's not mutation.  Because of that
# the search pass will get confused if we mutate as we go.  So once
# we find a match we do all the changes, swap out the rule and move on.
def jam_inlines_into_seq(seq):
    # here we just build the replacement sequence
    result = []
    for j, tok in enumerate(seq):
        if type(tok) is str and tok in INLINE_RULES:
           value = rule_defs[tok][0]
           for v in value:
               result.append(v)
        else:
           result.append(tok)
    return result

# Inline where needed to avoid conflicts
def apply_inlining():
    # Enumerate all the rules, visit each choice and each token in the choice.
    # if the token is a string and it is in the INLINE_RULES, replace it with
    # the value of the rule.
    for _, rule in rule_defs.items():
        for i, choice in enumerate(rule):
            for _, tok in enumerate(choice):
                if type(tok) is str and tok in INLINE_RULES:
                    rule[i] = jam_inlines_into_seq(choice)
                    break

    # Mark the inlined rules as visited so we do not emit them.
    # All references to this rule are gone now so it is for sure useless.
    for name in INLINE_RULES:
        del rule_defs[name]
        rules_visited.add(name)


def process_one_rule(name):
    choices = []

    # compute the various choices for this rule
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
            sequence = "seq({})".format(", ".join(seq))

            # long sequences are broken into lines for readability
            if len(sequence) > 100:
                choices.append("seq(\n          {})".format(",\n          ".join(seq)))
            else:
                choices.append(sequence)

    # If there is only one choice, we don't need to wrap it in a choice().
    if len(choices) == 1:
        rule_str = choices[0]
    else:
        rule_str = "choice(\n      {})".format(",\n      ".join(choices))

    # If the rule has post processing we apply it here. This is usually
    # to resolve conflicts in the grammar with the precedence function.
    if name in APPLY_FUNC_LIST:
        rule_str = APPLY_FUNC_LIST[name].format(rule_str)

    # Add the rule to the tree-sitter grammar.
    add_ts_rule(name, "$ => {}".format(rule_str))

# Here we convert the processed rules into tree-sitter grammar.
# We process the rules in the order they were seen in the grammar file.
# This is what 'sorted_rules' means in this context.
def compute_ts_grammar():

    # the rules may appear more than once in the grammar the choices are already
    # constructed in the rule_defs so we just need to visit the rule once.
    for name in sorted_rule_names:
        if name not in rules_visited:
            rules_visited.add(name)
            process_one_rule(name)

############ MAIN ############

# Read, inline, transform, and emit the tree-sitter grammar.

with open(input_filename) as fp:
    read_rule_defs(fp)

apply_inlining()

compute_ts_grammar()

# We are ready to emit the tree-sitter grammar.

print("""/**
 *
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

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
  rules: {""")

print(FIXED_RULES)

for ts in grammar.keys():
    if ts not in DELETED_PRODUCTIONS:
        print("    {}: {},\n".format(ts, grammar[ts]))

for ts in synthesized_tokens.keys():
    if ts not in DELETED_PRODUCTIONS:
        print("    {},\n".format(synthesized_tokens[ts]))

print("""/* This has to go last so that it is less favorable than keywords */
    ID: $ => /[_A-Za-z][A-Za-z0-9_]*/,
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
