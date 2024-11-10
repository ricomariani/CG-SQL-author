/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Assorted definitions for the CQL abstract syntax tree

#define AST_EMIT_DEFS 1

#include "cql.h"
#include "minipool.h"
#include "ast.h"
#include "sem.h"
#include "gen_sql.h"
#include "cg_common.h"
#include "encoders.h"
#include "cql.y.h"

// uncomment for HEX
// #define AST_EMIT_HEX 1

// uncomment to check parent values as the ast is walked
// #define EMIT_BROKEN_AST_WARNING 1

// uncomment to print the AST only
//    this is helpful if the ast is temporarily broken and
//    you want to look at it without getting asserts in
//    the gen_one_statement code path
//
// #define SUPPRESS_STATEMENT_ECHO

cql_data_defn( minipool *ast_pool );
cql_data_defn( minipool *str_pool );
cql_data_defn( char *_Nullable current_file );
cql_data_defn( bool_t macro_expansion_errors );

static symtab *macro_table;
static symtab *macro_arg_table;
static symtab *macro_refs;
static symtab *macro_defs;
static symtab *macro_arg_refs;
static symtab *macro_arg_types;

typedef struct macro_state_t {
  CSTR name;
  CSTR file;
  int32_t line;
  struct macro_state_t *parent;
  symtab *args;
} macro_state_t;

static macro_state_t macro_state;

// Helper object to just hold info in find_attribute_str(...) and find_attribute_num(...)
typedef struct misc_attrs_type {
  CSTR attribute_name;
  void * context;
  find_ast_str_node_callback str_node_callback;
  find_ast_num_node_callback num_node_callback;
  bool_t presence_only;
  uint32_t count;
} misc_attrs_type;

#undef MACRO_INIT
#define MACRO_INIT(x) \
  symtab_add(macro_refs, k_ast_ ## x ## _macro_ref, (void*)k_ast_ ## x ## _macro_arg); \
  symtab_add(macro_arg_refs, k_ast_ ## x ## _macro_arg_ref, (void*)k_ast_ ## x ## _macro_arg); \
  symtab_add(macro_defs, k_ast_ ## x ## _macro_def, (void*)k_ast_ ## x ## _macro_ref ); \
  symtab_add(macro_arg_types, k_ast_ ## x ## _macro_arg, (void*)k_ast_ ## x ## _macro_arg_ref )

// initialization for the ast and macro expansion pass
cql_noexport void ast_init() {
  minipool_open(&ast_pool);
  minipool_open(&str_pool);
  macro_table = symtab_new();
  macro_defs = symtab_new();
  macro_refs = symtab_new();
  macro_arg_refs = symtab_new();
  macro_arg_types = symtab_new();
  delete_macro_formals();
  macro_expansion_errors = false;

  MACRO_INIT(expr);
  MACRO_INIT(stmt_list);
  MACRO_INIT(query_parts);
  MACRO_INIT(cte_tables);
  MACRO_INIT(select_core);
  MACRO_INIT(select_expr);
  MACRO_INIT(unknown);

  macro_state.line = -1;
  macro_state.file = "<Unknown>";
  macro_state.name = "None";
  macro_state.parent = NULL;
}

cql_noexport void ast_cleanup() {
  delete_macro_formals();
  SYMTAB_CLEANUP(macro_table);
  SYMTAB_CLEANUP(macro_defs);
  SYMTAB_CLEANUP(macro_refs);
  SYMTAB_CLEANUP(macro_arg_refs);
  SYMTAB_CLEANUP(macro_arg_types);
  minipool_close(&ast_pool);
  minipool_close(&str_pool);
  run_lazy_frees();
}

// When a rewrite begins outside the context of normal parsing we do not
// know what file and line number should be attributed to the new nodes.
// This tells us.
cql_noexport void ast_set_rewrite_info(int32_t lineno, CSTR filename) {
  yylineno = lineno;
  current_file = (char *)filename;
}

// When we're done with a rewrite we do not want the old info to linger
// so it is immediately cleaned up.  The macros assert that the state is clean.
cql_noexport void ast_reset_rewrite_info() {
  yylineno = -1;
  current_file = NULL;
}

// Any number node
cql_noexport bool_t is_ast_num(ast_node *node) {
  return node && (node->type == k_ast_num);
}

// The integer node is not for numeric integers in the grammar
// This is used where there is an enumeration of values like
// a join type that can be represented as an int.  We don't
// store numbers like this because it would require us to
// faithfully parse all the hard cases and since we're just
// going to re-emit them anyway it seems silly to avoid
// lossless encode and decode when we can just store the string.
// Hence this is not for numerics.
cql_noexport bool_t is_ast_int(ast_node *node) {
  return node && (node->type == k_ast_int);
}


// Any of the various string payloads
// * identifiers
// * string literals
// * quoted string literals
// * macro names
cql_noexport bool_t is_ast_str(ast_node *node) {
  return node && (node->type == k_ast_str);
}

// A blob literal, only valid in SQL contexts.
// We don't allow blob literals in other contexts
// because there is no way to emit such a literal
// without a runtime initializer which we aren't
// willing to do.
cql_noexport bool_t is_ast_blob(ast_node *node) {
  return node && (node->type == k_ast_blob);
}

// This is a quoted identifier `foo bar`
cql_noexport bool_t is_qid(ast_node *node) {
  return is_ast_str(node) && ((str_ast_node *)node)->str_type == STRING_TYPE_QUOTED_ID;
}

// The special @RC node
cql_noexport bool_t is_at_rc(ast_node *node) {
  return is_ast_str(node) && !Strcasecmp("@RC", ((str_ast_node *)node)->value);
}

// The special @PROC node
cql_noexport bool_t is_proclit(ast_node *node) {
  return is_ast_str(node) && !Strcasecmp("@PROC", ((str_ast_node *)node)->value);
}

// Any string literal (they are alway normalized to SQL format, 'xyz')
cql_noexport bool_t is_strlit(ast_node *node) {
  return is_ast_str(node) && ((str_ast_node *)node)->value[0] == '\'';
}

// Any normal identifier (could be `foo`)
cql_noexport bool_t is_id(ast_node *node) {
  return is_ast_str(node) && ((str_ast_node *)node)->value[0] != '\'';
}

// The root name types foo and foo.bar
cql_noexport bool_t is_id_or_dot(ast_node *node) {
  return is_id(node) || is_ast_dot(node);
}

// Any of the leaf types
cql_noexport bool_t is_primitive(ast_node *node) {
  return is_ast_num(node) || is_ast_str(node) || is_ast_blob(node) || is_ast_int(node);
}

// Any of the procedure types (create or declare)
cql_noexport bool_t is_proc(ast_node *node) {
  return is_ast_create_proc_stmt(node) || is_ast_declare_proc_stmt(node);
}

// Any of the region types
cql_noexport bool_t is_region(ast_node *ast) {
  return is_ast_declare_schema_region_stmt(ast) || is_ast_declare_deployable_region_stmt(ast);
}

// Any of the select forms
cql_noexport bool_t is_select_stmt(ast_node *ast) {
  return is_ast_select_stmt(ast) ||
         is_ast_explain_stmt(ast) ||
         is_ast_select_nothing_stmt(ast) ||
         is_ast_with_select_stmt(ast);
}

// Any of the delete forms
cql_noexport bool_t is_delete_stmt(ast_node *ast) {
  return is_ast_delete_stmt(ast) ||
         is_ast_with_delete_stmt(ast);
}

// Any of the update forms
cql_noexport bool_t is_update_stmt(ast_node *ast) {
  return is_ast_update_stmt(ast) ||
         is_ast_with_update_stmt(ast);
}

// Any of the insert forms
cql_noexport bool_t is_insert_stmt(ast_node *ast) {
  return is_ast_insert_stmt(ast) ||
         is_ast_with_insert_stmt(ast) ||
         is_ast_upsert_stmt(ast) ||
         is_ast_with_upsert_stmt(ast);
}

// True if there is left node and it is not null
// This is handy for tree walks.  Primtives have
// and they are normally processed as ast_node *
// even though they are not.  They have effectively
// a common base type.  But left/right is not in it.
cql_noexport bool_t ast_has_left(ast_node *node) {
  if (is_primitive(node)) {
    return false;
  }
  return (node->left != NULL);
}

// As above, right node.
cql_noexport bool_t ast_has_right(ast_node *node) {
  if (is_primitive(node)) {
    return false;
  }
  return (node->right != NULL);
}

// Sets the right node but also sets the parent node of the node
// on the right to the new parent.  Always use this helper because
// code invariably forgets to set the parent causing a broken tree
// otherwise.
cql_noexport void ast_set_right(ast_node *parent, ast_node *right)  {
  parent->right = right;
  if (right) {
    right->parent = parent;
  }
}

// As above, left node.
cql_noexport void ast_set_left(ast_node *parent, ast_node *left) {
  parent->left = left;
  if (left) {
    left->parent = parent;
  }
}

// Create a new ast node witht he given left and right.
// Sets the file and line number from the global state
// Sets the parent node of the provided children to the new node.
cql_noexport ast_node *new_ast(const char *type, ast_node *left, ast_node *right) {
  Contract(current_file && yylineno > 0);
  ast_node *ast = _ast_pool_new(ast_node);
  ast->type = type;
  ast->left = left;
  ast->right = right;
  ast->lineno = yylineno;
  ast->filename = current_file;
  ast->sem = NULL;

  if (left) left->parent = ast;
  if (right) right->parent = ast;

  return ast;
}

// Reflecting the fact that this is information about a
// fact in the AST and not a number it's called new_ast_option
// for option.
cql_noexport ast_node *new_ast_option(int32_t value) {
  Contract(current_file && yylineno > 0);
  int_ast_node *iast = _ast_pool_new(int_ast_node);
  iast->type = k_ast_int;
  iast->value = value;
  iast->lineno = yylineno;
  iast->filename = current_file;
  iast->sem = NULL;
  return (ast_node *)iast;
}

// Create a new string node for a string literal
// These are sql literals by default so we use
// that string type.
cql_noexport ast_node *new_ast_str(CSTR value) {
  Contract(current_file && yylineno > 0);
  Contract(value);
  str_ast_node *sast = _ast_pool_new(str_ast_node);
  sast->type = k_ast_str;
  sast->value = value;
  sast->lineno = yylineno;
  sast->filename = current_file;
  sast->sem = NULL;
  sast->str_type = STRING_TYPE_SQL;
  return (ast_node *)sast;
}

// Create a new numberic node.  As discussed above
// the numeric is encoded in string form.  We do not
// even try to normalize it.  This is especially important
// for floating point literals.  We do not want to lose
// anything between the CQL code and the target compiler.
// We assume that floating point processing might be slightly
// different in C vs. SQLite or Lua.  Hence we keep the constant
// fixed.
cql_noexport ast_node *new_ast_num(int32_t num_type, CSTR value) {
  Contract(current_file && yylineno > 0);
  Contract(value);
  num_ast_node *nast = _ast_pool_new(num_ast_node);
  nast->type = k_ast_num;
  nast->value = value;
  nast->lineno = yylineno;
  nast->filename = current_file;
  nast->sem = NULL;
  nast->num_type = num_type;
  Contract(nast->value);
  return (ast_node *)nast;
}

// Creates a new blob literal.  As with numerics we
// simply store the text of the literal and pass it through.
cql_noexport ast_node *new_ast_blob(CSTR value) {
  Contract(current_file && yylineno > 0);
  str_ast_node *sast = _ast_pool_new(str_ast_node);
  sast->type = k_ast_blob;
  sast->value = value;
  sast->lineno = yylineno;
  sast->filename = current_file;
  sast->sem = NULL;
  return (ast_node *)sast;
}

// Get the compound operator name.
// As with almost all other aspects of the AST the AST is known
// to be good by contract and this is enforced.  Any badly
// formed AST is not tolerated anywhere which keeps it clean.
cql_noexport CSTR get_compound_operator_name(int32_t compound_operator) {
  CSTR result = NULL;

  switch (compound_operator) {
    case COMPOUND_OP_EXCEPT:
      result = "EXCEPT";
      break;
    case COMPOUND_OP_INTERSECT:
      result = "INTERSECT";
      break;
    case COMPOUND_OP_UNION:
      result = "UNION";
      break;
    case COMPOUND_OP_UNION_ALL:
      result = "UNION ALL";
      break;
  }

  Invariant(result);
  return result;
}

// This converts C string literal syntax into SQL string literal syntax
// the test of the program expects the SQL style literals.  We support
// C style literals largely because they pass through the C pre-processor better.
// Even stuff like the empty string '' causes annoying warnings.  However
// the escaping is lightly different.  Also C string literals have useful escape sequences
cql_noexport CSTR convert_cstrlit(CSTR cstr) {
  CHARBUF_OPEN(decoded);
  CHARBUF_OPEN(encoded);
  cg_decode_c_string_literal(cstr, &decoded);
  cg_encode_string_literal(decoded.ptr, &encoded);

  CSTR result = Strdup(encoded.ptr);
  CHARBUF_CLOSE(encoded);
  CHARBUF_CLOSE(decoded);
  return result;
}

// Just like SQL string literal but we record
// that the origin of the string was the C format.
// When we decode this node we will format it
// in the C way.  But in the AST it's stored in
// the SQL way.
cql_noexport ast_node *new_ast_cstr(CSTR value) {
  value = convert_cstrlit(value);
  str_ast_node *sast = (str_ast_node *)new_ast_str(value);
  sast->str_type = STRING_TYPE_C;
  return (ast_node *)sast;
}

// This makes a new QID node starting from already escaped
// ID text.  So for instance `a b` is X_aX20b.  We do
// not escaped the text again or wrap it in quotes.
// We verify that it looks like escaped text.
cql_noexport ast_node *new_ast_qstr_escaped(CSTR value) {
  Contract(value);
  Contract(value[0] != '`');

  str_ast_node *sast = (str_ast_node *)new_ast_str(value);
  sast->str_type = STRING_TYPE_QUOTED_ID;
  return (ast_node *)sast;
}

// This makes a new QID node starting form the quoted
// identifier like `a b`.  We have to escape it first
// and then we store that name.  Lots of the code is
// oblivious to the fact that the id was escaped.  e.g.
// All the C  and Lua codegen correctly uses the escaped
// name and never deals with unescaping.  This means
// the bulk of the compiler doesn't have to know about
// the escaping.  The exceptions are the forgatting code
// in gen_sql and the ast building code in rewrite.c
cql_noexport ast_node *new_ast_qstr_quoted(CSTR value) {
  Contract(value);
  Contract(value[0] == '`');
  ast_node *result;

  CHARBUF_OPEN(encoded);
    cg_encode_qstr(&encoded, value);
    result = new_ast_qstr_escaped(Strdup(encoded.ptr));
  CHARBUF_CLOSE(encoded);

  return result;
}

// for indenting, it just holds spaces.
static char padbuffer[4096];


// Emits the value of the node if it is a leaf node.
// Returns true such a value was emitted.
cql_noexport bool_t print_ast_value(struct ast_node *node) {
  bool_t ret = false;

  if (is_ast_str(node)) {
    EXTRACT_STRING(str, node);

#ifdef AST_EMIT_HEX
    cql_output("%llx: ", (long long)node);
#endif
    cql_output("%s", padbuffer);
    if (is_strlit(node)) {
      cql_output("{strlit %s}", str);
    }
    else {
      if (is_qid(node)) {
        CHARBUF_OPEN(tmp);
          cg_decode_qstr(&tmp, str);
          cql_output("{name %s}", tmp.ptr);
        CHARBUF_CLOSE(tmp);
      }
      else {
        cql_output("{name %s}", str);
      }
    }
    ret = true;
  }

  if (is_ast_num(node)) {
#ifdef AST_EMIT_HEX
    cql_output("%llx: ", (long long)node);
#endif
    cql_output("%s", padbuffer);

    EXTRACT_NUM_TYPE(num_type, node);
    EXTRACT_NUM_VALUE(val, node);

    if (num_type == NUM_BOOL) {
      cql_output("{bool %s}", val);
    }
    else if (num_type == NUM_INT) {
      cql_output("{int %s}", val);
    }
    else if (num_type == NUM_LONG) {
      cql_output("{longint %s}", val);
    }
    else if (num_type == NUM_REAL) {
      cql_output("{dbl %s}", val);
    }
    ret = true;
  }

  if (is_ast_blob(node)) {
#ifdef AST_EMIT_HEX
    cql_output("%llx: ", (long long)node);
#endif
    EXTRACT_BLOBTEXT(value, node);
    cql_output("%s", padbuffer);
    cql_output("{blob %s}", value);
    ret = true;
  }

  if (is_ast_int(node)) {
#ifdef AST_EMIT_HEX
    cql_output("%llx: ", (long long)node);
#endif
    cql_output("%s", padbuffer);

    // The join type case is common enough that we have special code for it.
    // The rest are just formatted as a number.
    int_ast_node *inode = (int_ast_node *)node;
    cql_output("{int %lld}", (llint_t)inode->value);
    if (node->parent->type == k_ast_join_target) {
      CSTR out = NULL;
      switch (inode->value) {
        case JOIN_INNER:       out = "{join_inner}";       break;
        case JOIN_CROSS:       out = "{join_cross}";       break;
        case JOIN_LEFT_OUTER:  out = "{join_left_outer}";  break;
        case JOIN_RIGHT_OUTER: out = "{join_right_outer}"; break;
        case JOIN_LEFT:        out = "{join_left}";        break;
        case JOIN_RIGHT:       out = "{join_right}";       break;
      }
      Contract(out); // if this fails there is a bogus join type in the AST
      cql_output(" %s", out);
    }
    ret = true;
  }

  if (ret && node->sem) {
    cql_output(": ");
    print_sem_type(node->sem);
  }

  if (ret) {
    cql_output("\n");
  }

  return ret;
}

// Prints the node type and the semantic info if there is any
cql_noexport void print_ast_type(ast_node *node) {
  cql_output("%s", padbuffer);
  cql_output("{%s}", node->type);
  if (node->sem) {
    cql_output(": ");
    print_sem_type(node->sem);
  }
  cql_output("\n");
}

// Helper function to get the parameters node out of the ast for a proc.
cql_noexport ast_node *get_proc_params(ast_node *ast) {
  Contract(is_ast_create_proc_stmt(ast) || is_ast_declare_proc_stmt(ast));
  // works for both
  EXTRACT_NOTNULL(proc_params_stmts, ast->right);
  EXTRACT(params, proc_params_stmts->left);
  return params;
}

// Helper function to get the proc name from a declare_proc_stmt or create_proc_stmt
cql_noexport ast_node *get_proc_name(ast_node *ast) {
  if (is_ast_create_proc_stmt(ast)) {
    return ast->left;
  }

  Contract(is_ast_declare_proc_stmt(ast));
  EXTRACT_NOTNULL(proc_name_type, ast->left);
  return proc_name_type->left;
}

cql_noexport bool_t is_select_func(ast_node *ast) {
  return is_ast_declare_select_func_no_check_stmt(ast) || is_ast_declare_select_func_stmt(ast);
}

cql_noexport bool_t is_non_select_func(ast_node *ast) {
  return is_ast_declare_func_no_check_stmt(ast) || is_ast_declare_func_stmt(ast);
}

// Helper function to get the parameters node out of the ast for a func.
cql_noexport ast_node *get_func_params(ast_node *ast) {
  Contract(is_select_func(ast) || is_non_select_func(ast));

  EXTRACT_NOTNULL(func_params_return, ast->right);
  EXTRACT(params, func_params_return->left);
  return params;
}

// Helper function to extract the list of attribute.
// Walk through a misc_attrs node and call the callbacks :
//  - find_ast_misc_attr_callback if misc_attr node is found
// Let's take the example below and see what values will be passed to callbacks
// e.g:
//  @attribute(cql:foo=(baa, (name, 'nelly')))
//  @attribute(cql:base=raoul)
//  create procedure sample()
//  begin
//    select * from baa;
//  end;
//
//  1- find_ast_misc_attr_callback("cql", "foo", <(baa, (name, 'nelly'))>, <context>)
//  2- find_ast_misc_attr_callback("cql", "foo", <raoul>, <context>)
//  3- End
cql_noexport void find_misc_attrs(
  ast_node *_Nullable ast_misc_attrs,
  find_ast_misc_attr_callback _Nonnull misc_attr_callback,
  void *_Nullable context)
{
  Contract(is_ast_misc_attrs(ast_misc_attrs));

  for (ast_node *misc_attrs = ast_misc_attrs; misc_attrs; misc_attrs = misc_attrs->right) {
    Invariant(is_ast_misc_attrs(misc_attrs));
    ast_node *misc_attr = misc_attrs->left;
    ast_node *misc_attr_key = misc_attr->left;
    ast_node *values = misc_attr->right;
    CSTR misc_attr_prefix = NULL;
    CSTR misc_attr_name = NULL;

    if (is_ast_dot(misc_attr_key)) {
      EXTRACT_STRING(prefix, misc_attr_key->left);
      EXTRACT_STRING(name, misc_attr_key->right);
      misc_attr_prefix = prefix;
      misc_attr_name = name;
    } else {
      EXTRACT_STRING(name, misc_attr_key);
      misc_attr_name = name;
    }

    Invariant(misc_attr_name);
    misc_attr_callback(misc_attr_prefix, misc_attr_name, values, context);
  }
}

// This callback helper dispatches matching string or list of string values
// for the indicated cql:attribute_name.  Non-string values are ignored in
// this path.  Note that the attribute might be badly formed hence there are
// few Contract enforcement here.  We can't crash if the value is unexpected
// we just don't recognize it as properly attributed for whatever (e.g. it just
// isn't a base fragment decl if it has an integer value for the fragment name)
static void ast_find_ast_misc_attr_callback(
  CSTR misc_attr_prefix,
  CSTR misc_attr_name,
  ast_node *ast_misc_attr_values,
  void *_Nullable context)
{
  misc_attrs_type* misc = (misc_attrs_type*) context;

  // First make sure that there is a prefix and name and that they match
  if (misc_attr_prefix &&
      misc_attr_name &&
      !Strcasecmp(misc_attr_prefix, "cql") &&
      !Strcasecmp(misc_attr_name, misc->attribute_name)) {

    // callback regardless of value, could be any payload
    if (misc->presence_only) {
      Invariant(!misc->str_node_callback);
      misc->count++;
      return;
    }

    // The attribute value might be a string or a list of strings.
    // Non-string, non-list attributes are ignored for this callback type
    if (is_ast_str(ast_misc_attr_values)) {
      if (misc->str_node_callback) {
        EXTRACT_STRING(value, ast_misc_attr_values);
        misc->str_node_callback(value, ast_misc_attr_values, misc->context);
      }
      misc->count++;
    }
    else if (is_ast_misc_attr_value_list(ast_misc_attr_values)) {
      for (ast_node *list = ast_misc_attr_values; list; list = list->right) {
        // any non-string values are ignored, loop over the rest calling on each string
        if (is_ast_str(list->left)) {
          EXTRACT_STRING(value, list->left);
          if (misc->str_node_callback) {
            misc->str_node_callback(value, list->left, misc->context);
          }
          misc->count++;
        }
      }
    } else if (is_ast_num(ast_misc_attr_values)) {
      if (misc->num_node_callback) {
        EXTRACT_NUM_VALUE(value, ast_misc_attr_values);
        misc->num_node_callback(value, ast_misc_attr_values, misc->context);
      }
    }
  }
}

// Helper function to extract the specified string type attribute (if any) from the misc attributes
// provided, and invoke the callback function
cql_noexport uint32_t find_attribute_str(
  ast_node *_Nonnull misc_attr_list,
  find_ast_str_node_callback _Nullable callback,
  void *_Nullable context,
  const char *attribute_name)
{
  Contract(is_ast_misc_attrs(misc_attr_list));

  misc_attrs_type misc = {
    .str_node_callback = callback,
    .context = context,
    .attribute_name = attribute_name,
    .count = 0,
  };

  find_misc_attrs(misc_attr_list, ast_find_ast_misc_attr_callback, &misc);
  return misc.count;
}

// check for the presence of the given attribute (duplicates are ok)
cql_noexport bool_t find_named_attr(ast_node *_Nonnull misc_attr_list, CSTR _Nonnull name) {
  Contract(is_ast_misc_attrs(misc_attr_list));

  misc_attrs_type misc = {
    .presence_only = 1,
    .attribute_name = name,
    .count = 0,
  };

  find_misc_attrs(misc_attr_list, ast_find_ast_misc_attr_callback, &misc);
  return !!misc.count;
}

// Helper function to extract the specified number type attribute (if any) from the misc attributes
// provided, and invoke the callback function
cql_noexport uint32_t find_attribute_num(
  ast_node *_Nonnull misc_attr_list,
  find_ast_num_node_callback _Nullable callback,
  void *_Nullable context,
  const char *attribute_name)
{
  Contract(is_ast_misc_attrs(misc_attr_list));

  misc_attrs_type misc = {
    .num_node_callback = callback,
    .context = context,
    .attribute_name = attribute_name,
    .count = 0,
  };

  find_misc_attrs(misc_attr_list, ast_find_ast_misc_attr_callback, &misc);
  return misc.count;
}

// This callback helper tests only if the attribute matches the search condition
// the value is irrelevant for this type of attribute
static void ast_exists_ast_misc_attr_callback(
  CSTR misc_attr_prefix,
  CSTR misc_attr_name,
  ast_node *ast_misc_attr_values,
  void *_Nullable context)
{
  misc_attrs_type* misc = (misc_attrs_type*) context;

  // First make sure that there is a prefix and name and that they match
  if (misc_attr_prefix &&
      misc_attr_name &&
      !Strcasecmp(misc_attr_prefix, "cql") &&
      !Strcasecmp(misc_attr_name, misc->attribute_name)) {
          misc->count++;
  }
}

// Helper function to return count of given string type attribute
// in the misc attributes provided
cql_noexport uint32_t exists_attribute_str(ast_node *_Nullable misc_attr_list, const char *attribute_name)
{
  if (!misc_attr_list) {
    return 0;
  }

  Contract(is_ast_misc_attrs(misc_attr_list));

  misc_attrs_type misc = {
    .str_node_callback = NULL,
    .context = NULL,
    .attribute_name = attribute_name,
    .count = 0,
  };

  find_misc_attrs(misc_attr_list, ast_exists_ast_misc_attr_callback, &misc);
  return misc.count;
}

// Helper function to extract the ok_table_scan nodes (if any) from the misc attributes
// provided, and invoke the callback function.
cql_noexport uint32_t find_ok_table_scan(
  ast_node *_Nonnull list,
  find_ast_str_node_callback _Nonnull callback,
  void *_Nullable context)
{
  return find_attribute_str(list, callback, context, "ok_table_scan");
}

cql_noexport uint32_t find_query_plan_branch(
  ast_node *_Nonnull list,
  find_ast_num_node_callback _Nonnull callback,
  void *_Nullable context
) {
  return find_attribute_num(list, callback, context, "query_plan_branch");
}

// Helper function to extract the auto-drop nodes (if any) from the misc attributes
// provided, and invoke the callback function.
cql_noexport uint32_t find_autodrops(
  ast_node *_Nonnull list,
  find_ast_str_node_callback _Nonnull callback,
  void *_Nullable context)
{
  return find_attribute_str(list, callback, context, "autodrop");
}

// Helper function to extract the identity columns (if any) from the misc attributes
// provided, and invoke the callback function
cql_noexport uint32_t find_identity_columns(
  ast_node *_Nullable misc_attr_list,
  find_ast_str_node_callback _Nonnull callback,
  void *_Nullable context)
{
  return find_attribute_str(misc_attr_list, callback, context, "identity");
}

// Helper function to select out the cql:alias_of attribute
// This is really only interesting to C codegen.  It forces the compiler
// to emit an extra #define as well as the function prototype so that
// some common native function can implement several equivalent but
// perhaps different by CQL type external functions.
cql_noexport uint32_t find_cql_alias_of(
  ast_node *_Nonnull misc_attr_list,
  find_ast_str_node_callback _Nonnull callback,
  void *_Nullable context)
{
  return find_attribute_str(misc_attr_list, callback, context, "alias_of");
}

// Helper function to extract the blob storage node (if any) from the misc attributes
cql_noexport bool_t find_blob_storage_attr(ast_node *_Nonnull misc_attr_list)
{
  return find_named_attr(misc_attr_list, "blob_storage");
}

// Helper function to extract the backing table node (if any) from the misc attributes
cql_noexport uint32_t find_backing_table_attr(ast_node *_Nonnull misc_attr_list)
{
  return find_named_attr(misc_attr_list, "backing_table");
}

// Helper function to extract the backed table node (if any) from the misc attributes
cql_noexport uint32_t find_backed_table_attr(ast_node *_Nonnull misc_attr_list)
{
  return find_attribute_str(misc_attr_list, NULL, NULL, "backed_by");
}

// helper to look for the blob storage attribute
cql_noexport bool_t is_table_blob_storage(ast_node *ast) {
  Contract(is_ast_create_table_stmt(ast) || is_ast_create_virtual_table_stmt(ast));
  EXTRACT_MISC_ATTRS(ast, misc_attrs);

  return misc_attrs && find_blob_storage_attr(misc_attrs);
}

// helper to look for the backed table attribute
cql_noexport bool_t is_table_backed(ast_node *ast) {
  Contract(is_ast_create_table_stmt(ast) || is_ast_create_virtual_table_stmt(ast));
  EXTRACT_MISC_ATTRS(ast, misc_attrs);

  return misc_attrs && find_backed_table_attr(misc_attrs);
}

// helper to look for the backing table attribute
cql_noexport bool_t is_table_backing(ast_node *ast) {
  Contract(is_ast_create_table_stmt(ast) || is_ast_create_virtual_table_stmt(ast));
  EXTRACT_MISC_ATTRS(ast, misc_attrs);

  return misc_attrs && find_backing_table_attr(misc_attrs);
}

// This can be easily called in the debugger
cql_noexport void print_root_ast(ast_node *node) {
  print_ast(node, NULL, 0, false);
}

cql_noexport void print_ast(ast_node *node, ast_node *parent, int32_t pad, bool_t flip) {
  if (pad == 0) {
    padbuffer[0] = '\0';
  }

  if (!node) {
    return;
  }

// Verifies that the parent pointer is corrent
#ifdef EMIT_BROKEN_AST_WARNING
  if (ast_has_right(node) && node->right->parent != node) {
    cql_output("%llx ast broken right", (long long)node);
    broken(node);
  }

  if (ast_has_left(node) && node->left->parent != node) {
    cql_output("%llx ast broken left", (long long)node);
    broken(node);
  }
#endif

  if (print_ast_value(node)) {
    return;
  }

  if (is_ast_stmt_list(parent) && is_ast_stmt_list(node)) {
    print_ast(node->left, node, pad, !node->right);
    print_ast(node->right, node, pad, 1);
  }
  else {
    if (pad == 2) {
      if (parent && is_ast_stmt_list(parent)) {
        EXTRACT_STMT_AND_MISC_ATTRS(stmt, misc_attrs, parent);

        if (options.hide_builtins && misc_attrs && find_named_attr(misc_attrs, "builtin")) {
          return;
        }

        cql_output("\n");
        cql_output("The statement ending at line %d\n\n", node->lineno);
        gen_stmt_level = 1;

        if (misc_attrs) {
          gen_misc_attrs_to_stdout(misc_attrs);
        }

        if (!options.ast_no_echo) {
          gen_one_stmt_to_stdout(stmt);
          cql_output("\n");
        }

#if defined(CQL_AMALGAM_LEAN) && !defined(CQL_AMALGAM_SEM)
        // sem off, nothing to print here
#else
        // print any error text
        if (stmt->sem && stmt->sem->sem_type == SEM_TYPE_ERROR && stmt->sem->error) {
          cql_output("%s\n", stmt->sem->error);
        }
#endif
      }
    }

#ifdef AST_EMIT_HEX
    cql_output("%llx: ", (long long)node);
#endif
    print_ast_type(node);
    if (flip && pad >= 2) {
      padbuffer[pad-2] = ' ';
    }
    if (pad == 0) {
      padbuffer[pad] = ' ';
    }
    else {
      padbuffer[pad] = '|';
    }
    padbuffer[pad+1] = ' ';
    padbuffer[pad+2] = '\0';
    print_ast(node->left, node, pad+2, !node->right);
    print_ast(node->right, node, pad+2, 1);
    padbuffer[pad] = '\0';
  }
}

// Recursively finds table nodes, executing the callback for each that is found.  The
// callback will not be executed more than once for the same table name.
cql_noexport void continue_find_table_node(table_callbacks *callbacks, ast_node *node) {
  // Check the type of node so that we can find the direct references to tables. We
  // can't know the difference between a table or view in the ast, so we will need to
  // later find the definition to see if it points to a create_table_stmt to distinguish
  // from views.

  find_ast_str_node_callback alt_callback = NULL;
  symtab *alt_visited = NULL;
  ast_node *table_or_view_name_ast = NULL;

  if (is_ast_cte_table(node)) {
    EXTRACT_ANY_NOTNULL(cte_body, node->right);

    // this is a proxy node, it doesn't contribute anything
    // any nested select does not run.
    if (is_ast_like(cte_body)) {
      return;
    }
  }
  else if (is_ast_shared_cte(node)) {
    // if we're on a shared CTE usage, then we recurse into the CALL and
    // we recurse into the binding list.  The CALL should not be handled
    // like a normal procedure call, the body is inlined.  Note that the
    // existence of the fragment is meant to be transparent to anyone
    // downstream -- this isn't a normal call that might be invisible to us
    // we *must* have the fragment because we're talking about a semantically
    // valid shared cte binding.

    EXTRACT_NOTNULL(call_stmt, node->left);
    EXTRACT(cte_binding_list, node->right);

    EXTRACT_NAME_AST(name_ast, call_stmt->left);
    EXTRACT_STRING(name, name_ast);
    ast_node *proc = find_proc(name);
    if (proc) {
      // Look through the proc definition for tables. Just call through recursively.
      continue_find_table_node(callbacks, proc);
    }

    if (cte_binding_list) {
      continue_find_table_node(callbacks, cte_binding_list);
    }

    // no further recursion is needed
    return;
  }
  else if (is_ast_declare_cursor_like_select(node)) {
    // There is a select in this declaration but it doesn't really run, it's just type info
    // so that doesn't count.  So we don't recurse here.
    return;
  }
  else if (is_ast_cte_binding(node)) {
    EXTRACT_ANY_NOTNULL(actual, node->left);

    // handle this just like a normal table usage in a select statement (because it is)
    table_or_view_name_ast = actual;
    alt_callback = callbacks->callback_from;
    alt_visited = callbacks->visited_from;
  }
  else if (is_ast_table_or_subquery(node)) {
    EXTRACT_ANY_NOTNULL(factor, node->left);
    if (is_ast_str(factor)) {
      // the other table factor cases (there are several) do not have a string payload
      table_or_view_name_ast = factor;
      alt_callback = callbacks->callback_from;
      alt_visited = callbacks->visited_from;
    }
  }
  else if (is_ast_fk_target(node)) {
    // if we're walking a table then we'll also walk its FK's
    // normally we don't start by walking tables anyway so this doesn't
    // run if you do a standard walk of a procedure
    if (callbacks->notify_fk) {
      EXTRACT_NAME_AST(name_ast, node->left);
      table_or_view_name_ast = name_ast;
    }
  }
  else if (is_ast_drop_view_stmt(node) || is_ast_drop_table_stmt(node)) {
    if (callbacks->notify_table_or_view_drops) {
      EXTRACT_NAME_AST(name_ast, node->right);
      table_or_view_name_ast = name_ast;
    }
  }
  else if (is_ast_trigger_target_action(node)) {
    if (callbacks->notify_triggers) {
      EXTRACT_NAME_AST(name_ast, node->left);
      table_or_view_name_ast = name_ast;
    }
  }
  else if (is_ast_delete_stmt(node)) {
    EXTRACT_NAME_AST(name_ast, node->left);
    table_or_view_name_ast = name_ast;
    alt_callback = callbacks->callback_deletes;
    alt_visited = callbacks->visited_delete;
  }
  else if (is_ast_insert_stmt(node)) {
    EXTRACT(name_columns_values, node->right);
    EXTRACT_NAME_AST(name_ast, name_columns_values->left);
    table_or_view_name_ast = name_ast;
    alt_callback = callbacks->callback_inserts;
    alt_visited = callbacks->visited_insert;
  }
  else if (is_ast_update_stmt(node)) {
    EXTRACT_ANY(name_ast, node->left);
    // name_ast node is NULL if update statement is part of an upsert statement
    if (name_ast) {
      table_or_view_name_ast = name_ast;
      alt_callback = callbacks->callback_updates;
      alt_visited = callbacks->visited_update;
    }
  }
  else if (is_ast_call_stmt(node) | is_ast_call(node)) {
    // Both cases have the name in the node left so we can consolidate
    // the check to see if it's a proc is redundant in the call_stmt case
    // but it lets us share code so we just go with it.  The other case
    // is a possible proc_as_func call so we must check if the target is a proc.

    EXTRACT_NAME_AST(name_ast, node->left);
    EXTRACT_STRING(name, name_ast);
    ast_node *proc = find_proc(name);

    if (proc) {
      // this only happens for ast_call but this check is safe for both
      if (name_ast->sem && (name_ast->sem->sem_type & SEM_TYPE_INLINE_CALL)) {
        // Look through the proc definition for tables because the target will be inlined
        continue_find_table_node(callbacks, proc);
      }

      EXTRACT_STRING(canon_name, get_proc_name(proc));
      if (callbacks->callback_proc) {
        if (symtab_add(callbacks->visited_proc, canon_name, proc)) {
          callbacks->callback_proc(canon_name, proc, callbacks->callback_context);
        }
      }
    }
  }

  if (table_or_view_name_ast) {
    // Find the definition and see if we have a create_table_stmt.
    EXTRACT_STRING(table_or_view_name, table_or_view_name_ast);
    ast_node *table_or_view = find_table_or_view_even_deleted(table_or_view_name);

    // It's not actually possible to use a deleted table or view in a procedure.
    // If the name lookup here says that we found something deleted it means
    // that we have actually found a CTE that is an alias for a deleted table
    // or view. In that case, we don't want to add the thing we found to the dependency
    // set we are creating.  We don't want to make this CTE an error because
    // its reasonable to replace a deleted table/view with CTE of the same name.
    // Hence we simply filter out deleted tables/views here.
    if (table_or_view && table_or_view->sem->delete_version > 0) {
      table_or_view = NULL;
    }

    // Make sure we don't process a table or view that we've already processed.
    if (table_or_view) {
      if (is_ast_create_table_stmt(table_or_view)) {
        EXTRACT_NOTNULL(create_table_name_flags, table_or_view->left);
        EXTRACT_STRING(canonical_name, create_table_name_flags->right);

        // Found a table, execute the callback.
        if (symtab_add(callbacks->visited_any_table, canonical_name, table_or_view)) {
          callbacks->callback_any_table(canonical_name, table_or_view, callbacks->callback_context);
        }

        // Emit the second callback if any.
        if (alt_callback && symtab_add(alt_visited, canonical_name, table_or_view)) {
          alt_callback(canonical_name, table_or_view, callbacks->callback_context);
        }
      } else {
        Contract(is_ast_create_view_stmt(table_or_view));
        EXTRACT_NOTNULL(view_and_attrs, table_or_view->right);
        EXTRACT_NOTNULL(view_details_select, view_and_attrs->left);
        EXTRACT_NOTNULL(view_details, view_details_select->left);
        EXTRACT_STRING(canonical_name, view_details->left);

        if (symtab_add(callbacks->visited_any_table, canonical_name, table_or_view)) {
          // Report the view itself
          if (callbacks->callback_any_view) {
            callbacks->callback_any_view(canonical_name, table_or_view, callbacks->callback_context);
          }

          if (!callbacks->do_not_recurse_views) {
            // Look through the view definition for tables. Just call through recursively.
            continue_find_table_node(callbacks, table_or_view);
          }
        }
      }
    }
  }

  // Check the left and right nodes.
  if (ast_has_left(node)) {
    continue_find_table_node(callbacks, node->left);
  }

  if (ast_has_right(node)) {
    continue_find_table_node(callbacks, node->right);
  }
}


// Find references in a proc and invoke the corresponding callback on them
// this is useful for dependency analysis.
cql_noexport void find_table_refs(table_callbacks *callbacks, ast_node *node) {
  // Each kind of callback needs its own symbol table because, for instance,
  // you might see a table as an insert and also as an update. If we use
  // a single visited table like we used to then the second kind of usage would
  // not get recorded.

  // Note: we don't need a seperate table for visiting views and visiting tables
  // any given name can only be a view or a table, never both.
  callbacks->visited_any_table = symtab_new();
  callbacks->visited_insert = symtab_new();
  callbacks->visited_update = symtab_new();
  callbacks->visited_delete = symtab_new();
  callbacks->visited_from = symtab_new();
  callbacks->visited_proc = symtab_new();

  continue_find_table_node(callbacks, node);

  if (callbacks->callback_final_processing) {
    callbacks->callback_final_processing(callbacks->callback_context);
  }

  SYMTAB_CLEANUP(callbacks->visited_any_table);
  SYMTAB_CLEANUP(callbacks->visited_insert);
  SYMTAB_CLEANUP(callbacks->visited_update);
  SYMTAB_CLEANUP(callbacks->visited_delete);
  SYMTAB_CLEANUP(callbacks->visited_from);
  SYMTAB_CLEANUP(callbacks->visited_proc);
}

cql_noexport size_t ends_in_cursor(CSTR str) {
  const char tail[] = " CURSOR";
  return Strendswith(str, tail) ? sizeof(tail) - 1 : 0;
}

cql_noexport size_t ends_in_set(CSTR str) {
  const char tail[] = " SET";
  return Strendswith(str, tail) ? sizeof(tail) - 1 : 0;
}

// store the discovered attribute in the given storage
static void record_string_value(CSTR _Nonnull name, ast_node *_Nonnull _misc_attr, void *_Nullable _context) {
  if (_context) {
    CSTR *target = (CSTR *)_context;
    *target = name;
  }
}

// Helper function extracts the named string fragment and gets its value as a string
// if there is no such attribute or the attribute is not a string you get NULL.
cql_noexport CSTR get_named_string_attribute_value(ast_node *_Nonnull misc_attr_list, CSTR _Nonnull name)
{
  CSTR result = NULL;
  find_attribute_str(misc_attr_list, record_string_value, &result, name);
  return result;
}

// Copy the whole tree recursively
cql_noexport ast_node *ast_clone_tree(ast_node *_Nullable ast) {
  if (!ast) {
     return NULL;
  }
  else if (is_ast_num(ast)) {
    num_ast_node *nast = _ast_pool_new(num_ast_node);
    *nast = *(num_ast_node *)ast;
    return (ast_node*)nast;
  }
  else if (is_ast_str(ast) || is_ast_blob(ast)) {
    str_ast_node *sast = _ast_pool_new(str_ast_node);
    *sast = *(str_ast_node *)ast;
    return (ast_node*)sast;
  }
  else if (is_ast_int(ast)) {
    int_ast_node *iast = _ast_pool_new(int_ast_node);
    *iast = *(int_ast_node *)ast;
    return (ast_node*)iast;
  }
  ast_node *_ast = _ast_pool_new(ast_node);
  *_ast = *ast;
  ast_set_left(_ast, ast_clone_tree(ast->left));
  ast_set_right(_ast, ast_clone_tree(ast->right));
  return _ast;
}

// a new macro body context has happened, clear
// the existing context and make a new symbol table
// for macro arguments.  This will be the x! and y!
// in @macro(expr) foo!(x! expr, y! expr)
cql_noexport void new_macro_formals() {
  delete_macro_formals();
  macro_arg_table = symtab_new();
}

// The macro body has ended, clean the symbol table
cql_noexport void delete_macro_formals() {
  SYMTAB_CLEANUP(macro_arg_table);
}

// A new macro definition has appeared we need to record:
//  * The name
//  * The type
//  * the ast node of the body
// The name in the table will be foo! so we add the ! to the symbol name
// From this point on foo! will resolve to a macro so it's not possible
// to redeclare foo! -- any such attempt will not look like an indentifer
// followed by a macro name.
cql_noexport bool_t set_macro_info(CSTR name, int32_t macro_type, ast_node *ast) {
  macro_info *minfo = _ast_pool_new(macro_info);
  minfo->def = ast;
  minfo->type = macro_type;

  return symtab_add(macro_table, name, minfo);
}

// Recover the macro info given the name (if it exists).
cql_noexport macro_info *get_macro_info(CSTR name) {
  symtab_entry *entry = symtab_find(macro_table, name);
  return entry ? (macro_info *)(entry->val) : NULL;
}

// As above, but for macro arguments.  These are the formal arguments
// of any macro. The processing is the same except that it goes in a different table.
// Duplicates lead to errors.
cql_noexport bool_t set_macro_arg_info(CSTR name, int32_t macro_type, ast_node *ast) {
  macro_info *minfo = _ast_pool_new(macro_info);
  minfo->def = ast;
  minfo->type = macro_type;
  return symtab_add(macro_arg_table, name, minfo);
}

// Recover the macro info given the name (if it exists).
cql_noexport macro_info *get_macro_arg_info(CSTR name) {
  symtab_entry *entry = symtab_find(macro_arg_table, name);
  return entry ? (macro_info *)(entry->val) : NULL;
}

cql_noexport bool_t is_any_macro_ref(ast_node *ast) {
  return is_macro_ref(ast) || is_macro_arg_ref(ast);
}

cql_noexport bool_t is_macro_ref(ast_node *ast) {
  return ast && !!symtab_find(macro_refs, ast->type);
}

cql_noexport bool_t is_macro_arg_ref(ast_node *ast) {
  return ast && !!symtab_find(macro_arg_refs, ast->type);
}

cql_noexport bool_t is_macro_def(ast_node *ast) {
  return ast && !!symtab_find(macro_defs, ast->type);
}

cql_noexport bool_t is_macro_arg_type(ast_node *ast) {
  return ast && !!symtab_find(macro_arg_types, ast->type);
}

// Look for the name first as an argument and then as a macro body.
// Note that at this point name will have the ! at the end already.
cql_noexport int32_t resolve_macro_name(CSTR name) {
  macro_info *minfo;
  if (macro_arg_table) {
    minfo = get_macro_arg_info(name);
    if (minfo) {
      return minfo->type;
    }
  }
  minfo = get_macro_info(name);
  return minfo ? minfo->type : EOF;
}

// A new macro is being defined.  We need to add the types of
// all of the parameter formals into the parameter table
cql_noexport CSTR install_macro_args(ast_node *macro_formals) {
  new_macro_formals();
  for ( ; macro_formals; macro_formals = macro_formals->right) {
    Contract(is_ast_macro_formals(macro_formals));
    EXTRACT_NOTNULL(macro_formal, macro_formals->left);

    EXTRACT_STRING(name, macro_formal->left);
    EXTRACT_STRING(type, macro_formal->right);

    // these are the only two cases for now
    int32_t macro_type = macro_type_from_str(type);
    bool_t success = set_macro_arg_info(name, macro_type, macro_formal);
    if (!success) {
      return name;
    }
  }

  return NULL;
}

// Replaces the new node for the old node in the tree by
// swapping it in as the child of the old node's parent.
// This isn't the preferred way to do node swapping,
// we normally wish to avoid changing the identify of
// the current node so in rewrite.c we almost always do
// old->type = new->type and then change the left and right
// but in this case it's normal, even common, for the node
// type to change to one of the leaf types and they are
// different sizes so we have to use the more general mechanism.
// This means we might have to refetch parent->left or right
// to get the new value of the node.
static void replace_node(ast_node *old, ast_node *new) {
  if (old->parent->left == old) {
   ast_set_left(old->parent, new);
  }
  else {
   ast_set_right(old->parent, new);
  }
}


// This is the trickier macro expansion case.  It happens for all
// the list types. Let's make it concrete by discussing it for
// statements and statement lists.  The grammar allows a statement
// list macro to appear anywhere a statement can appear.  Statements
// always happen inside of statement lists.  It sort of has to be
// that way because you want these to all work:
//
// while true         while true        while true
// begin              begin             begin
//   foo!();            other stuff;      foo!();
//   other stuff;       foo!();         end;
// end;               end;
//
// So basically the statement macro which is itself a list
// is in the tree where a statement belongs.  Let's make a quick picture:
//
// stmt_list[1]  <--- "parent" arg points here
//   macro!
//   stmt_list[2]  --> this could be nulll
//     other_stuff
//     NULL;
//
// After macro! is expanded we get this picture:
//
//     stmt_list[3]
//       macro_body[1]
//       stmt_list [4]  --> this could be nulll
//         macro_body[2]
//         NULL         --> final right pointer must link in
//
// We need to thread these together
// where macro! was in the tree macro_body[1] must go
// stmt_list[1]->right must be changed to point to stmt_list[4]
// The final right pointer (stmt_list[4] in this case) must
// point to stmt_list[2] to continue the chain.  The first left node
// of the body must become the first left node of the existing parent.
//
// This (which never actually fully exists)
//
// stmt_list[1]  <--- "parent" arg points here
//     stmt_list[3]
//       macro_body[1]
//       stmt_list [4]  --> this could be nulll
//         macro_body[2]
//         NULL         --> final right pointer must link in
//   stmt_list[2]  --> this could be nulll
//     other_stuff
//     NULL;
//
// Becomes:
//
// stmt_list[1]  <--- "parent" arg points here
//   macro_body[1]
//   stmt_list [4]  --> this could be nulll
//     macro_body[2]
//     stmt_list[2]  --> this could be nulll
//       other_stuff
//       NULL;
//
// i.e., it looks like an noraml statement list again.
// To do this we only need to change 3 pointers.
// As it happens, "it just works" even if some of those
// lists are abbreviated. For in stance maybe there is no
// stmt_list[4] or maybe there is no stmt_list[2].  These
// both just cut the list short just like they should.
//
// The same logic works for all the list types because they all
// have exactly the same shape.  In CQL, lists are a chain of right
// pointers with the payload on the left.
static bool_t spliced_macro_into_list(ast_node *parent, ast_node *new) {
  // if it isn't one of the list types, don't use this method
  if (!(
    is_ast_stmt_list(new) ||
    is_ast_cte_tables(new) ||
    is_ast_select_core_list(new) ||
    is_ast_select_expr_list(new))) {
      return false;
  }

  if (is_macro_arg_type(parent)) {
    return false;
  }

  // OK we have something that is like a list node already and
  // it is located where an item should be.  We just need to
  // unwrap it.

  // insert the new item into the list
  ast_set_left(parent, new->left);

  // march to the end of the "new" list
  ast_node *end = new;
  while (end->right) {
    end = end->right;
  }

  // link the end of the new list to what came after the new item
  ast_set_right(end, parent->right);
  ast_set_right(parent, new->right);
  return true;
}

// The arguments to @TEXT are either string literals, which we expand
// using the decode function or else they are macro pieces which we
// expand using gen_any_macro_expansion.  Either way they land
// unencoded into the output buffer.   The @TEXT handler will
// then quote them.
static void expand_text_args(charbuf *output, ast_node *text_args) {
  for (; text_args; text_args = text_args->right) {
    Contract(is_ast_text_args(text_args));
    EXTRACT_ANY_NOTNULL(txt, text_args->left);

    // string literals are handled specially because we need to
    // strip the quotes from them!
    if (is_strlit(txt)) {
      EXTRACT_STRING(str, txt);
      cg_decode_string_literal(str, output);
    }
    else {
      // everything else we just expand as usual

      expand_macros(txt);
      txt = text_args->left;

      gen_sql_callbacks callbacks;
      init_gen_sql_callbacks(&callbacks);
      callbacks.mode = gen_mode_echo;
      gen_set_output_buffer(output);
      gen_with_callbacks(txt, gen_any_text_arg, &callbacks);
    }
  }
}

// Report a macro-related error at the given spot with the given message
// We walk up the chain of macro expansions and report all those too
// because macro debugging is hard without this info.
static void report_macro_error(ast_node *ast, CSTR msg, CSTR subj) {
   cql_error("%s:%d:1: error: in %s : %s%s%s%s%s%s%s\n",
     ast->filename,
     ast->lineno,
     ast->type,
     msg,
     subj ? " (" : "",
     subj ? macro_type_from_name(subj) : "",
     subj ? ")" : "",
     subj ? " '" : "",
     subj,
     subj ? "'" : "");

  macro_state_t *p = &macro_state;
  while (p->parent) {
    cql_error(" -> '%s!' in %s:%d\n", p->name, p->file, p->line);
    p = p->parent;
  }
  macro_expansion_errors = 1;
}

// for @MACRO_FILE -- this gives us the file in which macro
// expansion began. Very useful for assert macros and such.
// Note that @MACRO_FILE doesn't yet support path trimming
// like @FILE but it will.
static CSTR get_macro_file() {
  macro_state_t *p = &macro_state;
  macro_state_t *prev = p;
  while (p->parent) {
    prev = p;
    p = p->parent;
  }
  return prev->file;
}

// for @MACRO_LINE -- this gives us the line in which macro
// expansion began. Very useful for assert macros and such.
static int32_t get_macro_line() {
  macro_state_t *p = &macro_state;
  macro_state_t *prev = p;
  while (p->parent) {
    prev = p;
    p = p->parent;
  }
  return prev->line;
}

// @ID(x) will take a given string and covert it into an identifier.
// Which is to say it will decode the string and verify that it is
// a legal identifier.  This operation is only interesting
// if the body of the @ID is @TEXT.  Any other body wouldn't have
// needed wrapping in the first place.  On interesting trick you
// can do with @ID is this.   The "bar" in "foo.bar" is NOT an
// expression, it's only a name.  Therefore an EXPR macro cannot
// be used there.  i.e.  foo.bar! doesn't work.  BUT foo.@ID(bar!)
// can work. Currently it has to be @ID(@TEXT(bar!)) but this
// will soon change.  @ID could assume the @TEXT if there is not
// one there.  @ID *is* a valid name so it can go in places
// expr! could not go.
static void expand_at_id(ast_node *ast) {
  Contract(is_ast_at_id(ast));

  CHARBUF_OPEN(str);
  expand_macros(ast->left);
  expand_text_args(&str, ast->left);

  CSTR p = str.ptr;
  bool_t ok = true;

  if (p[0] == '_' || (p[0] >= 'a' && p[0] <= 'z') || (p[0] >= 'A' && p[0] <= 'Z')) {
    p++;
    while (p[0]) {
      if (p[0] == '_' ||
         (p[0] >= 'a' && p[0] <= 'z') ||
         (p[0] >= 'A' && p[0] <= 'Z') ||
         (p[0] >= '0' && p[0] <= '9')) {
            p++;
           continue;
      }
      ok = false;
      break;
    }
  }
  else {
     ok = false;
  }

  if (!ok) {
    report_macro_error(ast, "@ID expansion is not a valid identifier", str.ptr);
  }

  replace_node(ast, new_ast_str(Strdup(str.ptr)));
  CHARBUF_CLOSE(str);
}

// Use the helper to concatenate the arguments then encode them as a string.
// We use C style literals because newlines etc. are likely in the output
// and so the resulting literal will be much more readable if it is escaped.
static void expand_at_text(ast_node *ast) {
  Contract(is_ast_macro_text(ast));

  CHARBUF_OPEN(tmp);
  CHARBUF_OPEN(quote);
  expand_text_args(&tmp, ast->left);
  cg_encode_string_literal(tmp.ptr, &quote);
  ast_node *new = new_ast_str(Strdup(quote.ptr));
  str_ast_node *sast = (str_ast_node *)new;
  sast->str_type = STRING_TYPE_C;
  replace_node(ast, new);
  CHARBUF_CLOSE(quote);
  CHARBUF_CLOSE(tmp);
}

// Handles the special identifiers @MACRO_LINE and @MACRO_FILE
// which need treatment in the macro pass.  @FILE and @LINE to not
// require the macro stack so they can be handled later like all
// the other constants.
static void expand_special_ids(ast_node *ast) {
  Contract(is_ast_str(ast));
  EXTRACT_STRING(name, ast);

  if (!strcmp(name, "@MACRO_LINE")) {
    ast_node *num = new_ast_num(NUM_INT, dup_printf("%d", get_macro_line()));
    replace_node(ast, num);
  }
  else if (!strcmp(name, "@MACRO_FILE")) {
    CHARBUF_OPEN(tmp);
    cg_encode_string_literal(get_macro_file(), &tmp);
    ast_node *new = new_ast_str(Strdup(tmp.ptr));
    replace_node(ast, new);
    CHARBUF_CLOSE(tmp);
  }
}

static void report_macro_inappropriate(ast_node *ast, CSTR name) {
  report_macro_error(ast, "macro or argument used where it is not allowed", name);
  return;
}

// Here we handle a discovered macro reference
// We have to do several things:
//  * clone the body of the macro or arg
//  * set up the macro arguments for expansion if it is a macro ref
//  * validate the arguments if necessary
//  * recursively expand the macro body
//  * link in the expanded body into the correct spot with one of the helpers
static void expand_macro_refs(ast_node *ast) {
  Contract(is_any_macro_ref(ast));
  EXTRACT_STRING(name, ast->left);

  ast_node *parent = ast->parent;

  // @TEXT and @ID take any macro, and the macro arg node is already checked when we
  // invoke the macros, so those are good universally, otherwise we check for context
  // for the macro types that can only appear in certain places
  if (!is_ast_text_args(parent) && !is_macro_arg_type(parent)) {

    bool wrong = false;

    // this tells us that the current macro is select_core
    bool_t select_core_macro = is_ast_select_core_macro_ref(ast) || is_ast_select_core_macro_arg_ref(ast);

    // this tell us that a select core macro can go there and only select core macros
    bool_t select_core_valid = is_ast_select_core_list(parent);

    // the location is ONLY valid for this macro type and this macro type is ONLY valid for this location
    // so if only one is true it's wrong.  If any are wrong it's an error
    wrong |= select_core_macro ^ select_core_valid;

    // these are all the other types

    bool_t stmt_list_macro = is_ast_stmt_list_macro_ref(ast) || is_ast_stmt_list_macro_arg_ref(ast);
    bool_t stmt_list_valid = is_ast_stmt_list(parent);
    wrong |= stmt_list_macro ^ stmt_list_valid;

    bool_t cte_tables_macro = is_ast_cte_tables_macro_ref(ast) || is_ast_cte_tables_macro_arg_ref(ast);
    bool_t cte_tables_valid = is_ast_cte_tables(parent);
    wrong |= cte_tables_macro ^ cte_tables_valid;

    bool_t select_expr_macro = is_ast_select_expr_macro_ref(ast) || is_ast_select_expr_macro_arg_ref(ast);
    bool_t select_expr_valid = is_ast_select_expr_list(parent);
    wrong |= select_expr_macro ^ select_expr_valid;

    // is_ast_update_from could work here but not supported in grammar yet
    // just || that in to the valid locations when it is supported
    bool_t query_parts_macro = is_ast_query_parts_macro_ref(ast) || is_ast_query_parts_macro_arg_ref(ast);
    bool_t query_parts_valid = is_ast_table_or_subquery(parent);
    wrong |= query_parts_macro ^ query_parts_valid;

    // having done all of those tests the only thing we didn't do was verify that the expr macro
    // appears where it belongs however we have now ruled out all macro insertion locations other
    // than the expr macro ones, which are legion. Anything other than an expr macro cannot appear
    // in other than its locked down locations and the locked down locations will not hold expr
    // macros so we have covered all locations.  This is why we check all the types and all
    // the locations every time.

    if (wrong) {
      report_macro_inappropriate(ast, name);
      return;
    }
  }

  macro_info *minfo = NULL;
  bool_t is_ref = is_macro_ref(ast);

  // we have either a macro ref or a macro arg ref, nothing else can be here
  if (is_ref) {
    EXTRACT(macro_args, ast->right);

    // expand the arguments to the macro before using them, if there are any
    if (macro_args) {
      expand_macros(macro_args);
    }

    // get the info, we need the definition of this macro
    minfo = get_macro_info(name);
  }
  else {
    // get the info, we need the definition of this macro argument
    minfo = get_macro_arg_info(name);
  }

  // the macro was never defined, it's unknown...
  if (!minfo) {
    report_macro_error(ast, "macro reference is not a valid macro", name);
    return;
  }

  Invariant(minfo);
  ast_node *copy = ast_clone_tree(minfo->def);

  // the body is handing off the right if we copied a macro def
  // it's on the left if we copied a macro arg
  ast_node *body = is_ref ? copy->right : copy->left;

  // save the current args and stuff for our new context and for error
  // reporting...
  macro_state_t macro_state_saved = macro_state;

  if (is_ref) {
    // It's a macro reference, we need to set up the argument values
    // We'll save the current macro args and replace them with the
    // new after validation.  The type and number must be correct.
    EXTRACT_NOTNULL(macro_name_formals, minfo->def->left);
    EXTRACT(macro_formals, macro_name_formals->right);
    EXTRACT_STRING(macro_name, macro_name_formals->left);
    EXTRACT(macro_args, ast->right);

    // we're going to recurse, link up the states so we have a stack of them
    // these are like our frame pointers.  We also remember the local names
    // and so forth.  This gives us much better diagnostics
    macro_state.parent = &macro_state_saved;
    macro_state.line = ast->lineno;
    macro_state.file = ast->filename;
    macro_state.name = macro_name;
    macro_arg_table = macro_state.args = symtab_new();

    // Loop over each formal, we match the type of the argument
    // that is provided against the formal that is required.
    // The number arguments and type of arguments must match exactly.
    while (macro_formals && macro_args) {
      EXTRACT_NOTNULL(macro_formal, macro_formals->left);
      EXTRACT_STRING(formal_name, macro_formal->left);
      EXTRACT_ANY_NOTNULL(macro_arg, macro_args->left);
      EXTRACT_STRING(type, macro_formal->right);

      int32_t macro_type = macro_type_from_str(type);
      set_macro_arg_info(formal_name, macro_type, macro_arg);

      if (macro_arg_type(macro_arg) != macro_type) {
        report_macro_error(macro_arg, "macro type mismatch in argument", formal_name);
        goto cleanup;
      }

      macro_formals = macro_formals->right;
      macro_args = macro_args->right;
    }

    // formals left -> not enough args
    if (macro_formals) {
      report_macro_error(macro_formals->left, "not enough arguments to macro", macro_name);
      goto cleanup;
    }

    // args left -> too many args
    if (macro_args) {
      report_macro_error(macro_args->left, "too many arguments to macro", macro_name);
      goto cleanup;
    }
  }

  // it's hugely important to expand what you're going to replace FIRST
  // and then slot it in. Otherwise the recursion is n^2 depth!!!
  expand_macros(body);

  // its normal for body to have been replaced in the tree, we re-compute it
  // so that we get the expanded version.  Same rules as before
  body = is_ref ? copy->right : copy->left;

  // the query parts are already under a table_or_subquery node
  // because of the macro position, if there is a redundant one
  // in the arg tree, skip it.  We don't need two such wrappers
  // it makes extra (()) in the output
  if (is_ast_table_or_subquery_list(body) && body->right == NULL) {
    EXTRACT_NOTNULL(table_or_subquery, body->left);
    if (is_ast_join_clause(table_or_subquery->left) && table_or_subquery->right == NULL) {
      body = table_or_subquery->left;
    }
  }

  // now we splice the expanded tree into the place where the macro was

  if (is_ast_text_args(parent)) {
    // easy case, we just plunk in the node
    replace_node(ast, body);
  }
  else if (spliced_macro_into_list(parent, body)) {
    // spliced_macro_into_list, it's done above
    // this is where we have something like a statement
    // list but it's in the place where a statement should
    // go. We have to hoist the statement list node out
    // and link it into the statements. All the list
    // types have this issue and they all work the same.
  }
  else  {
    // everything else is a direct subtree replace
    replace_node(ast, body);
  }

cleanup:
  if (macro_state.args != macro_state_saved.args && macro_state.args) {
    // delete the args if we made new ones
    symtab_delete(macro_state.args);
  }

  // node that we cloned the current state so this is a no-op if
  // we didn't recurse.  But it makes the flow cleaner.
  macro_state = macro_state_saved;
  macro_arg_table = macro_state.args;
}

// make a macro arg node of the correct type for the
// kind of macro_ref we have.  This lets us do
// foo!(a!, b!, c!) without having to specify the arg
// type like we usually do.  So arg forwarding is easier.
cql_noexport ast_node *new_macro_arg_node(ast_node *arg) {
   CSTR type = arg->type;
   CSTR node_type = k_ast_expr_macro_arg;
   symtab_entry *entry = symtab_find(macro_refs, type);
   if (!entry) {
     entry = symtab_find(macro_arg_refs, type);
   }
   if (entry) {
     node_type = (CSTR)entry->val;
   }
   return new_ast(node_type, arg, NULL);
}

// This is the main recursive workhorse.  It expands macros
// and macro related constructs in place.  Later passes do not
// see macros except for the macro definition nodes.  Which could
// actually have been removed also but we don't.  Maybe we will
// some day.  Later passes ignore those.
cql_export void expand_macros(ast_node *_Nonnull node) {
tail_recurse:
  if (!options.semantic && options.test && macro_state.line != -1) {
    // in test mode charge the whole macro to the expansion
    // so we can attribute the AST better
    node->lineno = macro_state.line;
  }

  if (is_ast_ifdef_stmt(node) || is_ast_ifndef_stmt(node)) {
    EXTRACT_ANY_NOTNULL(evaluation, node->left);
    EXTRACT_NOTNULL(pre, node->right);

    if (is_ast_is_true(evaluation)) {
       node = pre->left;
    }
    else {
       node = pre->right;
    }
    if (node)
      goto tail_recurse;
    return;
  }

  // do not recurse into macro definitions
  if (is_macro_def(node)) {
    return;
  }

  // handle @ID
  if (is_ast_at_id(node)) {
    expand_at_id(node);
    return;
  }

  // handle @TEXT
  if (is_ast_macro_text(node)) {
    expand_at_text(node);
    return;
  }

  // handle @MACRO_LINE and @MACRO_FILE
  if (is_ast_str(node)) {
    expand_special_ids(node);
    return;
  }

  // expand macros and macro arguments in place
  if (is_any_macro_ref(node)) {
    expand_macro_refs(node);
    return;
  }

  // Check the left and right nodes.
  if (ast_has_left(node)) {
    // If there is no right child we can do tail recursion on the left
    // this helps a little but it isn't that important, the
    // next one is the one that really matters.  There are lots of
    // AST1 nodes in the AST schema, this hits all of those.
    if (!ast_has_right(node)) {
      node = node->left;
      goto tail_recurse;
    }
    expand_macros(node->left);
  }

  // tail recursion here is super important becuase the statement list
  // and be very long and it is a chain of right pointers.  There might
  // be hundreds or even thousands of top level statements in a file.
  if (ast_has_right(node)) {
    // tail recursion
    node = node->right;
    goto tail_recurse;
  }
}
