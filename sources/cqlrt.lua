--[[
Copyright (c) Meta Platforms, Inc. and affiliates.

This source code is licensed under the MIT license found in the
LICENSE file in the root directory of this source tree.
--]]

-- the built in version of sqlite is compiled without this enable_load_extenion (via -DOMIT...)
-- so we will get this error
-- dlopen(/usr/local/lib/lua/5.4/lsqlite3.so, 0x0006): symbol not found in flat namespace '_sqlite3_enable_load_extension'
-- use the brew version instead

package.loadlib("/usr/local/opt/sqlite/lib/libsqlite3.dylib","*")
sqlite3 = require('lsqlite3')


-- we know about these codes, everything else is some error
CQL_OK = sqlite3.OK
CQL_ERROR = sqlite3.ERROR
CQL_DONE = sqlite3.DONE
CQL_ROW = sqlite3.ROW

CQL_ENCODED_TYPE_BOOL_NOTNULL = string.byte("F", 1)
CQL_ENCODED_TYPE_INT_NOTNULL = string.byte("I", 1)
CQL_ENCODED_TYPE_LONG_NOTNULL = string.byte("L", 1)
CQL_ENCODED_TYPE_DOUBLE_NOTNULL = string.byte("D", 1)
CQL_ENCODED_TYPE_STRING_NOTNULL = string.byte("S", 1)
CQL_ENCODED_TYPE_BLOB_NOTNULL = string.byte("B", 1)
CQL_ENCODED_TYPE_OBJECT_NOTNULL = string.byte("O", 1)
CQL_ENCODED_TYPE_BOOL = string.byte("f", 1)
CQL_ENCODED_TYPE_INT = string.byte("i", 1)
CQL_ENCODED_TYPE_LONG = string.byte("l", 1)
CQL_ENCODED_TYPE_DOUBLE = string.byte("d", 1)
CQL_ENCODED_TYPE_STRING = string.byte("s", 1)
CQL_ENCODED_TYPE_BLOB = string.byte("b", 1)
CQL_ENCODED_TYPE_OBJECT = string.byte("o", 1)

-- stored box data types that align with the semnatic types
CQL_DATA_TYPE_NULL = 0
CQL_DATA_TYPE_INT32 = 1
CQL_DATA_TYPE_INT64 = 2
CQL_DATA_TYPE_DOUBLE = 3
CQL_DATA_TYPE_BOOL = 4
CQL_DATA_TYPE_STRING = 5
CQL_DATA_TYPE_BLOB = 6
CQL_DATA_TYPE_OBJECT = 7
CQL_DATA_TYPE_CORE = 63
CQL_DATA_TYPE_ENCODED = 64
CQL_DATA_TYPE_NOT_NULL = 128

cql_data_type_decode = {
  [CQL_ENCODED_TYPE_BOOL_NOTNULL] = CQL_DATA_TYPE_BOOL | CQL_DATA_TYPE_NOT_NULL,
  [CQL_ENCODED_TYPE_INT_NOTNULL] = CQL_DATA_TYPE_INT32 | CQL_DATA_TYPE_NOT_NULL,
  [CQL_ENCODED_TYPE_LONG_NOTNULL] = CQL_DATA_TYPE_INT64 | CQL_DATA_TYPE_NOT_NULL,
  [CQL_ENCODED_TYPE_DOUBLE_NOTNULL] = CQL_DATA_TYPE_DOUBLE | CQL_DATA_TYPE_NOT_NULL,
  [CQL_ENCODED_TYPE_STRING_NOTNULL] = CQL_DATA_TYPE_STRING | CQL_DATA_TYPE_NOT_NULL,
  [CQL_ENCODED_TYPE_BLOB_NOTNULL] = CQL_DATA_TYPE_BLOB | CQL_DATA_TYPE_NOT_NULL,
  [CQL_ENCODED_TYPE_OBJECT_NOTNULL] = CQL_DATA_TYPE_OBJECT | CQL_DATA_TYPE_NOT_NULL,
  [CQL_ENCODED_TYPE_BOOL] = CQL_DATA_TYPE_BOOL,
  [CQL_ENCODED_TYPE_INT] = CQL_DATA_TYPE_INT32,
  [CQL_ENCODED_TYPE_LONG] = CQL_DATA_TYPE_INT64,
  [CQL_ENCODED_TYPE_DOUBLE] = CQL_DATA_TYPE_DOUBLE,
  [CQL_ENCODED_TYPE_STRING] = CQL_DATA_TYPE_STRING,
  [CQL_ENCODED_TYPE_BLOB] = CQL_DATA_TYPE_BLOB,
  [CQL_ENCODED_TYPE_OBJECT] = CQL_DATA_TYPE_OBJECT
}

CQL_BLOB_TYPE_BOOL   = 0  -- always big endian format in the blob
CQL_BLOB_TYPE_INT32  = 1  -- always big endian format in the blob
CQL_BLOB_TYPE_INT64  = 2  -- always big endian format in the blob
CQL_BLOB_TYPE_FLOAT  = 3  -- always IEEE 754 "double" (8 bytes) format in the blob
CQL_BLOB_TYPE_STRING = 4  -- string field in a blob
CQL_BLOB_TYPE_BLOB   = 5  -- blob field in a blob
CQL_BLOB_TYPE_ENTITY = 6  -- Reserved in case object support is needed; Currently unused.

-- each statment can have optional data associated with it
cql_stmt_data = {}
cql_stmt_meta = {}
setmetatable(cql_stmt_data, cql_stmt_meta)

-- the keys will be statements, data lives only as long as the statement does
cql_stmt_meta.__mode = "k"

-- The keys will be object ids (numbers) the values are statements
-- Data lives only as long as the statement.  We have to do this
-- two step funny business so that we can go from an object id to a statement
-- and then from the statement to the values for the id with everything
-- weak on the statement
cql_id_binding = {}
cql_id_binding_meta = {}
setmetatable(cql_id_binding, cql_id_binding_meta)
cql_id_binding_meta.__mode = "kv"

-- each binding gets its own id, with 2^64 and at one per ns we would
-- wrap around every 150 years... by which time wrapping is pretty safe
cql_next_id = 0;

-- the whole point of this function is to assign the value to the statement
-- in such a way that it will not be strongly held when when the statement is gone
function cql_set_aux_value_for_stmt(stmt, value)
  -- if we ever want to be multi-threaded this has to be interlocked
  cql_next_id = cql_next_id + 1

  id = cql_next_id
  cql_id_binding[id] = stmt
  if cql_stmt_data[stmt] == nil then
    cql_stmt_data[stmt] = {}
  end
  -- this value will go away when the stmt goes away
  cql_stmt_data[stmt][id] = value
  return id
end

function cql_get_aux_value_for_id(id)
  -- get the statement if it exists, get statement data if it exists
  -- these are weak so it's possible to ask after the statement expired
  -- this isn't fatal but we need to give nil back in those cases
  local stmt = cql_id_binding[id]
  if stmt ~= nil then
     local stmt_data = cql_stmt_data[stmt]
     if stmt_data ~= nil then
        return stmt_data[id]
     end
  end
  return nil
end

-- cql_printf is the SQLite printf and it is far too expensive for general use
-- use only when demanded by printf function calls
function printf(...)
  io.write(cql_printf(...))
end

function cql_is(x,y)
   if x == nil and y == nil then
     return true;
   end

   if x == y then
     return true
   end

   -- normalize bools to 0/1 for comparison
   if x == true then x = 1 end;
   if x == false then x = 0 end;
   if y == true then y = 1 end;
   if y == false then y = 0 end;

   return x == y
end

function cql_is_not(x,y)
  return not cql_is(x,y)
end

function cql_eq(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x == y
  end
end

function cql_blob_eq(x,y)
  -- identity comparison for now
  return cql_eq(x,y)
end

function cql_blob_is_eq(x,y)
  -- identity comparison for now
  return x == y
end

function cql_ne(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x ~= y
  end
end

function cql_blob_ne(x,y)
  -- identity comparison for now
  return cql_ne(x,y)
end

function cql_blob_is_ne(x,y)
  -- identity comparison for now
  return x ~= y
end

function cql_ge(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x >= y
  end
end

function cql_gt(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x > y
  end
end

function cql_le(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x <= y
  end
end

function cql_lt(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x < y
  end
end

function cql_logical_and(x,y)
  if cql_is_false(x) or cql_is_false(y) then
    return false;
  elseif x == nil or y == nil then
    return nil
  else
    return true
  end
end

function cql_logical_or(x,y)
  if cql_is_true(x) or cql_is_true(y) then
    return true
  elseif x == nil or y == nil then
    return nil
  else
    return false
  end
end

function cql_shortcircuit_and(x,y)
  if cql_is_false(x) then
    return false
  else
    return cql_logical_and(x, y())
  end
end

function cql_shortcircuit_or(x,y)
  if cql_is_true(x) then
    return true
  else
    return cql_logical_or(x, y())
  end
end

function cql_add(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x + y;
  end
end

function cql_sub(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x - y;
  end
end

function cql_mul(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x * y;
  end
end

function cql_div(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x / y;
  end
end

function cql_idiv(x,y)
  if x == nil or y == nil then
    return nil
  end

  local sign = 1
  if x < 0 then
    sign =  -1
    x = -x
  end

  if y < 0 then
    sign = -sign
    y = -y
  end

  if sign < 0 then
    return -(x // y)
  else
    return (x // y)
  end
end

function cql_mod(x,y)
  if x == nil or y == nil then
    return nil
  end

  local sign = 1
  if x < 0 then
    sign = -1
    x = -x
  end

  if y < 0 then
    y = -y
  end

  if sign < 0 then
    return -(x % y)
  else
    return (x % y)
  end
end

function cql_lshift(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x << y;
  end
end

function cql_rshift(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x >> y;
  end
end

function cql_bin_and(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x & y;
  end
end

function cql_bin_or(x,y)
  if x == nil or y == nil then
    return nil
  else
    return x | y;
  end
end

function cql_is_true(x)
  return x ~= nil and x ~= 0 and x ~= false;
end

function cql_is_not_true(x)
  return x == nil or x == 0 or x == false;
end

function cql_is_false(x)
  return x == 0 or x == false
end

function cql_is_not_false(x)
  return x ~= 0 and x ~= false
end

function cql_like(x, y)
  if x == nil or y == nil then
    return nil
  end

  local db = sqlite3.open_memory()
  local stmt = db:prepare("SELECT ? LIKE ?")
  stmt:bind(1, x);
  stmt:bind(2, y);
  stmt:step()
  local result = stmt:get_value(0)
  stmt:finalize()
  db:close()
  return cql_to_bool(result)
end;

function cql_unary_sign(x)
  if x == nil then return nil end
  if x == true then return 1 end
  if x == false then return 0 end
  if x < 0 then return -1 end
  if x > 0 then return 1 end
  return 0
end

function cql_unary_not(x)
  if x == nil then return nil end
  return not x
end

function cql_unary_uminus(x)
  if x == nil then return nil end
  return -x
end

function cql_unary_abs(x)
  if x == nil then return nil end
  if x == true then return true end
  if x == false then return false end
  if x < 0 then return -x end
  return x
end

function cql_to_num(b)
  if b == nil then return nil; end
  if b then return 1 end;
  return 0
end

function cql_to_bool(n)
  if n == nil then return nil; end
  if n == false then return false end
  return n ~= 0;
end

function cql_clone_row(row)
  local result = {}
  local k
  local v

  for k, v in pairs(row) do
    result[k] = v
  end
  return result
end

function cql_get_blob_size(blob)
  return #blob
end

-- this needs better error handling
-- the normal SQLite printf is not exposed to lua so we emulate it with a select statement
-- this is not cheap... but it's the only compatible choice
function cql_printf(...)
  args = {...}
  -- no args, empty string result
  if #args == 0 or args[1] == "" then return "" end

  cmd = "select printf(?"
  for i= 2, #args do cmd = cmd .. ",?" end;
  cmd = cmd .. ");"

  -- dummy database
  local db = sqlite3.open_memory()
  local stmt = db:prepare(cmd)
  for i= 1, #args
  do
    stmt:bind(i, args[i])
  end;
  stmt:step()
  local result = stmt:get_value(0)
  stmt:finalize()
  db:close()
  return result
end

function cql_finalize_stmt(stmt)
  if stmt ~= nil then
    stmt:finalize()
  end
end

function cql_prepare(db, sql)
  local stmt = db:prepare(sql)
  return db:errcode(), stmt
end

function cql_get_value(stmt, col)
  return stmt:get_value(col)
end

function cql_no_rows_stmt(db, sql)
  return cql_prepare(db, "select 1 where 0")
end

function cql_step(stmt)
  return stmt:step()
end

function cql_reset_stmt(stmt)
  return stmt:reset()
end

function cql_exec(db, sql)
  return db:exec(sql)
end

function cql_bind_one(stmt, bind_index, value, code)
  if value == nil then
    rc = stmt:bind(bind_index, nil)
  elseif code == CQL_ENCODED_TYPE_OBJECT or code == CQL_ENCODED_TYPE_OBJECT_NOTNULL then
    rc = stmt:bind(bind_index, cql_set_aux_value_for_stmt(stmt, value))
  elseif code == CQL_ENCODED_TYPE_BLOB or code == CQL_ENCODED_TYPE_BLOB_NOTNULL then
    rc = stmt:bind_blob(bind_index, value)
  else
    rc = stmt:bind(bind_index, value)
  end
  return rc;
end

function cql_multibind(db, stmt, types, ...)
  -- values to bind come in as varargs
  local rc = sqlite3.OK
  local count = select('#', ...)
  for i = 1, count
  do
    local code = string.byte(types, i, i)
    local column = select(i,...)
    rc = cql_bind_one(stmt, i, column, code)
    if rc ~= sqlite3.OK then break end
  end;

  return rc
end

function cql_prepare_var(db, frag_count, frag_preds, frags)
  sql = ""
  for i = 1, frag_count
  do
     if frag_preds == nil or frag_preds[i-1] then
       sql = sql .. frags[i]
     end
  end
  local stmt = db:prepare(sql)
  return db:errcode(), stmt
end

function cql_exec_var(db, frag_count, frag_preds, frags)
  sql = ""
  for i = 1, frag_count
  do
     if frag_preds == nil or frag_preds[i-1] then
       sql = sql .. frags[i]
     end
  end
  return db:exec(sql)
end

function cql_multibind_var(db, stmt, bind_count, bind_preds, types, ...)
  -- values to bind come in as varargs
  local bind_index = 1
  local rc = sqlite3.OK
  local count = select('#', ...)
  for i = 1, count
  do
    if bind_preds[i-1] then
      local code = string.byte(types, i, i)
      local column = select(i,...)
      rc = cql_bind_one(stmt, bind_index, column, code)
      if rc ~= sqlite3.OK then break end
      bind_index = bind_index + 1
    end
  end;
  return rc
end

cql_disable_tracing = false

function cql_error_trace(rc, db)
  if cql_disable_tracing then
    return
  end

  if db:errcode() ~= 0 then
    print("err: ", rc, "db info:", db:errcode(), db:errmsg())
  else
    print("err: ", rc, "thrown exception")
  end
end

function cql_empty_cursor(result, types, columns)
  local byte
  local data

  for i = 1, #columns
  do
      byte = string.byte(types, i)
      data = nil;
      if byte == CQL_ENCODED_TYPE_BOOL_NOTNULL then
        data = false
      elseif byte == CQL_ENCODED_TYPE_INT_NOTNULL then
        data = 0
      elseif byte == CQL_ENCODED_TYPE_LONG_NOTNULL then
        data = 0
      elseif byte == CQL_ENCODED_TYPE_DOUBLE_NOTNULL then
        data = 0.0
      end
      result[columns[i]] = data
  end
  result._has_row_ = false
end

function cql_multifetch(stmt, result, types, columns)
  result._has_row_ = false
  rc = stmt:step()
  if rc ~= sqlite3.ROW then
    cql_empty_cursor(result, types, columns)
  else
    for i = 1, stmt:columns()
    do
      local data = stmt:get_value(i-1)
      local code = string.byte(types, i, i)

      if code == CQL_ENCODED_TYPE_DOUBLE or code == CQL_ENCODED_TYPE_DOUBLE_NOTNULL then
        data = cql_to_float(data)
      elseif code == CQL_ENCODED_TYPE_BOOL or code == CQL_ENCODED_TYPE_BOOL_NOTNULL then
        data = cql_to_bool(data)
      end

      result[columns[i]] = data
    end

    result._has_row_ = true
  end

  return rc
end

function cql_fetch_all_rows(stmt, types, columns)
  local rc
  local result_set = {}

  repeat
    local result = {}
    rc = cql_multifetch(stmt, result, types, columns)
    if rc ~= sqlite3.ROW then break end;
    table.insert(result_set, result)
  until false

  if rc ~= sqlite3.DONE then
     result_set = nil
  else
     rc = sqlite3.OK
  end
  return rc, result_set
end

function cql_to_integer(num)
  if num == true then return 1 end
  if num == false then return 0 end
  if num == nil then return nil end
  return math.floor(num);
end;

function cql_to_float(num)
  if num == true then return 1.0 end
  if num == false then return 0.0 end
  if num == nil then return nil end
  return 0.0 + num;
end;

function cql_to_bool(num)
  if num == false then return false end
  if num == nil then return nil end
  return num ~= 0
end;

function cql_contract_argument_notnull(arg, index)
  if arg == nil then
    print("arg is null -- index", index)
    exit_on_error();
  end
end

function cql_partition_create()
  return {};
end;

function cql_make_str_key(key_table, fields)
  local key = ""
  for i = 1, #fields
  do
    k = fields[i]
    v = key_table[k]
    key = key .. ":" .. tostring(v)
  end
  return key
end

function cql_hash_string(str)
  local hash = 0;
  local len = #str
  for i=1, len
  do
    byte = string.byte(str, i);
    hash = ((hash << 5) | (hash >> 59)) ~ byte;
  end
  return hash
end

function cql_cursor_hash(key, key_types, key_fields)
  if key == nil or not key._has_row_ then
     return 0
  end

  return cql_hash_string(cql_make_str_key(key, key_fields))
end

function cql_cursors_equal(k1, k1_types, k1_fields, k2, k2_types, k2_fields)
  if k1_types ~= k2_types then return false end
  if k1 == nil and k2 == nil then return true end
  if k1 == nil or k2 == nil then return false end
  if (not k1._has_row_) and not k2._has_row_ then return true end
  if (not k1._has_row_) or not k2._has_row_ then return false end
  if #k1 ~= #k2 then return false end

  for k,v in pairs(k1)
  do
     if v ~= k2[k] then return false end
  end

  return true
end

function cql_partition_cursor(partition, key, key_types, key_fields, cursor, cursor_types, cursor_fields)
  if not cursor._has_row_ then return false end
  key = cql_make_str_key(key, key_fields)
  cursor = cql_clone_row(cursor)
  if partition[key] ~= nil then
     table.insert(partition[key], cursor)
  else
     partition[key] = {cursor}
  end
  return true
end;

function cql_extract_partition(partition, key, key_types, key_fields)
  key = cql_make_str_key(key, key_fields)
  if partition[key] ~= nil then
     return partition[key]
  else
     if partition.__empty__ == nil then
       partition.__empty__ = {}
     end
     return partition.__empty__
  end
end

function cql_facets_create()
  return {}
end

function cql_facet_find(facets, facet)
   local result = facets[facet]
   if result ~= nil then
     return result
   else
     return -1
   end
end

function cql_facet_upsert(facets, facet, value)
   facets[facet] = value
   return true
end

function cql_facet_add(facets, facet, value)
   if facets[facet] ~= nil then return false end
   facets[facet] = value
   return true
end

function cql_string_dictionary_create()
  return {}
end

function cql_string_dictionary_add(dict, key, val)
  if dict[key] ~= nil then
    dict[key] = val
    return false
  end
  dict[key] = val
  return true
end

function cql_string_dictionary_find(dict, key)
  return dict[key]
end

-- in Lua, the string dictionary is the same, we can steal the implementation
cql_object_dictionary_create = cql_string_dictionary_create
cql_object_dictionary_add = cql_string_dictionary_add
cql_object_dictionary_find = cql_string_dictionary_find

-- in Lua, the string dictionary is the same, we can steal the implementation
cql_long_dictionary_create = cql_string_dictionary_create
cql_long_dictionary_add = cql_string_dictionary_add
cql_long_dictionary_find = cql_string_dictionary_find

-- in Lua, the string dictionary is the same, we can steal the implementation
cql_real_dictionary_create = cql_string_dictionary_create
cql_real_dictionary_add = cql_string_dictionary_add
cql_real_dictionary_find = cql_string_dictionary_find

-- in Lua, the string dictionary is the same, we can steal the implementation
cql_blob_dictionary_create = cql_string_dictionary_create
cql_blob_dictionary_add = cql_string_dictionary_add
cql_blob_dictionary_find = cql_string_dictionary_find

function cql_string_list_create()
  return {}
end

function cql_string_list_count(list)
  return #list
end

function cql_string_list_add(list, str)
  table.insert(list, str)
  return list
end

function cql_string_list_get_at(list, i)
  -- one based index
  return list[i+1]
end

function cql_string_list_set_at(list, i, val)
  -- one based index
  list[i+1] = val
  return list
end

-- the long/real/blob versions are the same in Lua
cql_long_list_create = cql_string_list_create;
cql_long_list_count = cql_string_list_count;
cql_long_list_add = cql_string_list_add;
cql_long_list_get_at = cql_string_list_get_at;
cql_long_list_set_at = cql_string_list_set_at;

cql_real_list_create = cql_string_list_create;
cql_real_list_count = cql_string_list_count;
cql_real_list_add = cql_string_list_add;
cql_real_list_get_at = cql_string_list_get_at;
cql_real_list_set_at = cql_string_list_set_at;

cql_blob_list_create = cql_string_list_create;
cql_blob_list_count = cql_string_list_count;
cql_blob_list_add = cql_string_list_add;
cql_blob_list_get_at = cql_string_list_get_at;
cql_blob_list_set_at = cql_string_list_set_at;

function cql_exec_internal(db, str)
  return db:exec(str)
end

function _cql_contains_column_def(haystack, needle)
  if haystack == nil or needle == nil then return false end
  local i
  local j
  i, j = string.find(haystack, needle)
  if i == nil or i < 2 then return false end
  local ch = string.sub(haystack, i-1, i-1)
  return ch == "(" or ch == " "
end

function cql_best_error(err)
  if err == sqlite3.OK then
    return sqlite3.ERROR
  else
    return err
  end
end

function cql_changes(db)
  return db:changes()
end

function cql_last_insert_rowid(db)
  return db:last_insert_rowid()
end

function cql_cursor_column_count(C, types, fields)
  return #fields
end

function cql_cursor_column_type(C, types, fields, i)
  local type = -1
  if i >= 0 and i < #fields then
    i = i + 1
    local code = string.byte(types, i, i)
    type = cql_data_type_decode[code]
  end
  return type
end

function cql_cursor_get_any(C, types, fields, i, reqd)
  if i >= 0 and i < #fields then
    i = i + 1
    local code = string.byte(types, i, i)
    local type = cql_data_type_decode[code] & CQL_DATA_TYPE_CORE
    if type == reqd then
      return C[fields[i]]
    end
  end

  return null
end;

function cql_cursor_get_bool(C, types, fields, i)
  return cql_cursor_get_any(C, types, fields, i, CQL_DATA_TYPE_BOOL)
end

function cql_cursor_get_int(C, types, fields, i)
  return cql_cursor_get_any(C, types, fields, i, CQL_DATA_TYPE_INT32)
end

function cql_cursor_get_long(C, types, fields, i)
  return cql_cursor_get_any(C, types, fields, i, CQL_DATA_TYPE_INT64)
end

function cql_cursor_get_real(C, types, fields, i)
  return cql_cursor_get_any(C, types, fields, i, CQL_DATA_TYPE_DOUBLE)
end

function cql_cursor_get_text(C, types, fields, i)
  return cql_cursor_get_any(C, types, fields, i, CQL_DATA_TYPE_STRING)
end

function cql_cursor_get_blob(C, types, fields, i)
  return cql_cursor_get_any(C, types, fields, i, CQL_DATA_TYPE_BLOB)
end

function cql_cursor_get_object(C, types, fields, i)
  return cql_cursor_get_any(C, types, fields, i, CQL_DATA_TYPE_OBJECT)
end

function cql_cursor_format(C, types, fields)
  local result = ""
  for i = 1, #fields
  do
    if i ~= 1 then result = result.."|" end
    result = result..fields[i]..":"
    local code = string.byte(types, i, i)
    local value = C[fields[i]]
    if value == nil then
      result = result.."null"
    else
      if code == CQL_ENCODED_TYPE_BLOB_NOTNULL or code == CQL_ENCODED_TYPE_BLOB then
        result = result.."length "..tostring(#value).." blob"
      else
        result = result..tostring(value)
      end
    end
  end
  return result
end

function _cql_create_upgrader_input_statement_list(str, parse_word)
  local list = {}

  if #str == 0 then return list end
  local space = string.byte(" ")
  local quote = string.byte("'")
  local lineStartIt = 1
  while string.byte(str, lineStartIt) == space
  do
    lineStartIt = lineStartIt + 1
  end

  local in_quote = false
  for i = 1, #str do
    local p = string.byte(str, i)
    if in_quote then
      if p == quote then
        if p == quote then
          i = i + 1;
        else
          in_quote = false
        end
      end
    elseif p == quote then
      in_quote = true
    elseif not in_quote and i == string.find(str, parse_word, i) then
      if lineStartIt ~= i then
        currLine = string.sub(str, lineStartIt, i-1)
        table.insert(list, currLine)
        lineStartIt = i
      end
    end
  end
  currLine = string.sub(str, lineStartIt, #str)
  table.insert(list, currLine)
  return list
end

function _cql_create_table_name_from_table_creation_statement(create)
  local virtual_table_prefix = "CREATE VIRTUAL TABLE "
  local i = 0
  local space = string.byte(" ")
  local close_bracket = string.byte("]")
  local open_bracket = string.byte("[")
  local start = 1
  while string.byte(create, start) == space do
    start = start + 1;
  end

  if start == string.find(create, virtual_table_prefix, start) then
    print("invariant violated, virtual tables cannot go into recreate groups")
    exit_on_error();
  else
    i = string.find(create, "[(]")  -- it's a pattern
  end

  while string.byte(create, i-1) == space do
    i = i - 1
  end

  local lineStartIt = i


  if string.byte(create, lineStartIt - 1) == close_bracket then
    -- handle [foo bar] names
    while string.byte(create, lineStartIt - 1) ~= open_bracket do
      lineStartIt = lineStartIt - 1;
    end
    lineStartIt = lineStartIt - 1;
  else
    -- handle normal names (go back to the space)
    while string.byte(create, lineStartIt - 1) ~= space do
      lineStartIt = lineStartIt - 1;
    end
  end

  return string.sub(create, lineStartIt, i-1)
end


function _cql_create_table_name_from_index_creation_statement(index_create)
  local needle = "ON "
  local lineStartIt = string.find(index_create, needle) + #needle
  local i = string.find(index_create, "[(]")
  local space = string.byte(" ")
  while string.byte(index_create, i-1) == space do
    i = i - 1
  end
  return string.sub(index_create, lineStartIt, i-1);
end


function cql_rebuild_recreate_group(db, tables, indices, deletes)
  local tableList = _cql_create_upgrader_input_statement_list(tables, "CREATE ");
  local indexList = _cql_create_upgrader_input_statement_list(indices, "CREATE ");
  local deleteList = _cql_create_upgrader_input_statement_list(deletes, "DROP ");

  local rc = sqlite3.OK
  -- these are deleted or unsubscribed tables
  -- note that tables in the list are in create order, so we reverse to get drop order
  for i = #deleteList, 1, -1 do
    rc = cql_exec(db, deleteList[i])
    if rc ~= sqlite3.OK then return rc end
  end
  -- drop all the tables we are going to recreate, we have to drop in the reverse order
  -- tables are in create order in this list
  for i = #tableList, 1, -1 do
    local table_name = _cql_create_table_name_from_table_creation_statement(tableList[i])
    local drop = "DROP TABLE IF EXISTS "
    drop = drop .. table_name
    rc = cql_exec(db, drop)
    if rc ~= sqlite3.OK then return rc end
  end
  -- now create all the tables we need (list is in create order)
  for i = 1, #tableList do
    rc = cql_exec(db, tableList[i])
    if rc ~= sqlite3.OK then return rc end
    local table_name = _cql_create_table_name_from_table_creation_statement(tableList[i])
    for j = 1, #indexList do
      local index_table_name = _cql_create_table_name_from_index_creation_statement(indexList[j])
      if table_name == index_table_name then
        rc = cql_exec(db, indexList[j])
        if rc ~= sqlite3.OK then return rc end
      end
    end
  end
  -- returning result = false (because we went with recreate plan)
  return rc, false
end

function cql_udf_stub(context)
end

function cql_create_udf_stub(db, name)
  -- make a stub udf function that does nothing
  db:create_function(name, -1, cql_udf_stub)
  rc = db:errcode()
  if rc ~= sqlite3.OK then
    cql_error_trace(rc, db)
  end
  return rc
end

-- this global will hold all the emitted constants
_cql = {}

-- this could be replaced in a custom cqlrt to store the constants anywhere you like
function cql_emit_constants(type, name, values)
  -- make _cql.enum or _cql.const etc. if needed
  if _cql[type] == nil then
    _cql[type] = {}
  end
  _cql[type][name] = values
end

-- This will "throw" in the CQL sense if rc != 0
function cql_throw(db, rc)
   return rc;
end;

function cql_box_int(x)
  return {[CQL_DATA_TYPE_INT32] = x}
end

function cql_box_long(x)
  return {[CQL_DATA_TYPE_INT64] = x}
end

function cql_box_real(x)
  return {[CQL_DATA_TYPE_DOUBLE] = x}
end

function cql_box_bool(x)
  return {[CQL_DATA_TYPE_BOOL] = x}
end

function cql_box_text(x)
  return {[CQL_DATA_TYPE_STRING] = x}
end

function cql_box_blob(x)
  return {[CQL_DATA_TYPE_BLOB] = x}
end

function cql_box_object(x)
  return {[CQL_DATA_TYPE_OBJECT] = x}
end

function cql_box_get_type(x)
  if x == nil then
    return CQL_DATA_TYPE_NULL
  end
  for k,v in pairs(x) do
    return k
  end

  return CQL_DATA_TYPE_NULL
end

function cql_unbox_int(x)
  if x == nil then
    return nil
  end
  return x[CQL_DATA_TYPE_INT32]
end

function cql_unbox_long(x)
  if x == nil then
    return nil
  end
  return x[CQL_DATA_TYPE_INT64]
end

function cql_unbox_real(x)
  if x == nil then
    return nil
  end
  return x[CQL_DATA_TYPE_DOUBLE]
end

function cql_unbox_bool(x)
  if x == nil then
    return nil
  end
  return x[CQL_DATA_TYPE_BOOL]
end

function cql_unbox_text(x)
  if x == nil then
    return nil
  end
  return x[CQL_DATA_TYPE_STRING]
end

function cql_unbox_blob(x)
  if x == nil then
    return nil
  end
  return x[CQL_DATA_TYPE_BLOB]
end

function cql_unbox_object(x)
  if x == nil then
    return nil
  end
  return x[CQL_DATA_TYPE_OBJECT]
end

function cql_setbit(x, i)
  local offset = 1 + i // 8
  local bit = i % 8
  x[offset] = x[offset] | (1<<bit)
end

function cql_getbit(x, i)
  local offset = 1 + i // 8
  local bit = i % 8
  if offset > #x then
    return nil
  end
  return cql_is_true(x[offset] & (1<<bit))
end

function cql_zigzag_encode_32(x)
  return cql_zigzag_encode_64(x) & 0xFFFFFFFF
end

function cql_zigzag_encode_64(x)
  if x < 0 then
    return (x << 1) ~ -1
  end
  return x << 1
end

function cql_zigzag_decode(x)
  return (x >> 1) ~ -(x & 1)
end

function cql_varint_encode(x)
  local result = {}
  while x > 0 or #result == 0 do
    local b = x & 0x7F
    x = x >> 7
    if x > 0 then
      b = b | 0x80
    end
    table.insert(result, b)
  end
  result = string.char(table.unpack(result))
  return result;
end

function cql_int_encode_32(x)
  return cql_varint_encode(cql_zigzag_encode_32(x))
end

function cql_int_encode_64(x)
  return cql_varint_encode(cql_zigzag_encode_64(x))
end

function cql_serialize_blob(C, C_types, C_fields)
  local bool_count = 0
  local var_encoding_count = 0
  local nullable_count = 0
  local header = {}
  local pieces = {}
  local bits = {}

  -- output starts with null terminated types
  table.insert(header, C_types)
  table.insert(header, "\0")

  -- We need to count bools and nullable types to figure out how many bytes we
  -- need for the bit vector. We want to pre-allocate the bytes we will need.
  -- Bools get stored in the bit vector. The is null state is stored in the bit
  -- vector for nullable types.  We do not have an actual payload if the value
  -- is a bool or null.  Note that a nullable bool uses both bits.
  for i = 1, #C_types do
    local code = string.byte(C_types, i)
    if code == CQL_ENCODED_TYPE_BOOL_NOTNULL or code == CQL_ENCODED_TYPE_BOOL then
      bool_count = bool_count + 1;
    end
    if code >= string.byte("a") then
      nullable_count = nullable_count + 1;
    end
  end

  -- this is our bit vector, it will be emitted as bytes
  bytes = (nullable_count + bool_count + 7) // 8
  for i = 1, bytes do
    table.insert(bits, 0)
  end

  local nullable_index = 0
  local bool_index = 0

  -- now we emit the actual data
  for i = 1, #C_types do
    local code = string.byte(C_types, i)
    local field = C_fields[i]
    local value = C[field]

    if code == CQL_ENCODED_TYPE_BOOL_NOTNULL then
      if value == nil then
         return -1, ""
      end
      if cql_is_true(value) then
        cql_setbit(bits, nullable_count + bool_index)
      end
      bool_index = bool_index + 1
    elseif code == CQL_ENCODED_TYPE_BOOL then
      if value ~= nil then
        cql_setbit(bits, nullable_index)
        if cql_is_true(value) then
          cql_setbit(bits, nullable_count + bool_index)
        end
      end
      nullable_index = nullable_index + 1
      bool_index = bool_index + 1
    elseif code == CQL_ENCODED_TYPE_INT_NOTNULL then
      if value == nil then
         return -1, ""
      end
      table.insert(pieces, cql_int_encode_32(value))
    elseif code == CQL_ENCODED_TYPE_INT then
      if value ~= nil then
        cql_setbit(bits, nullable_index)
        table.insert(pieces, cql_int_encode_32(value))
      end
      nullable_index = nullable_index + 1
    elseif code == CQL_ENCODED_TYPE_LONG_NOTNULL then
      if value == nil then
         return -1, ""
      end
      table.insert(pieces, cql_int_encode_64(value))
    elseif code == CQL_ENCODED_TYPE_LONG then
      if value ~= nil then
        cql_setbit(bits, nullable_index)
        table.insert(pieces, cql_int_encode_64(value))
      end
      nullable_index = nullable_index + 1
    elseif code == CQL_ENCODED_TYPE_STRING_NOTNULL then
      if value == nil then
         return -1, ""
      end
      table.insert(pieces, string.pack("z", value))
    elseif code == CQL_ENCODED_TYPE_STRING then
      if value ~= nil then
        cql_setbit(bits, nullable_index)
        table.insert(pieces, string.pack("z", value))
      end
      nullable_index = nullable_index + 1
    elseif code == CQL_ENCODED_TYPE_BLOB_NOTNULL then
      if value == nil then
         return -1, ""
      end
      table.insert(pieces, cql_int_encode_32(#value))
      table.insert(pieces, value)
    elseif code == CQL_ENCODED_TYPE_BLOB then
      if value ~= nil then
        cql_setbit(bits, nullable_index)
        table.insert(pieces, cql_int_encode_32(#value))
        table.insert(pieces, value)
      end
      nullable_index = nullable_index + 1
    elseif code == CQL_ENCODED_TYPE_DOUBLE_NOTNULL then
      if value == nil then
         return - 1, ""
      end
      table.insert(pieces, string.pack("d", value))
    elseif code == CQL_ENCODED_TYPE_DOUBLE then
      if value ~= nil then
        cql_setbit(bits, nullable_index)
        table.insert(pieces, string.pack("d", value))
      end
      nullable_index = nullable_index + 1
    end
  end

  table.insert(header, string.char(table.unpack(bits)))

  result = table.concat(header)..table.concat(pieces)
  return 0, result
end

function format_as_hex(str)
  local hex_output = {}
  local printable_output = {}

  for i = 1, #str do
      local byte = string.byte(str, i)
      -- Convert byte to hex
      table.insert(hex_output, string.format("%02X", byte))

      -- Check if the byte is printable (ASCII range 32-126)
      if byte >= 32 and byte <= 126 then
          -- If printable, store the character
          table.insert(hex_output, string.char(byte)..",")
      else
          -- If not printable, store a placeholder (like -)
          table.insert(hex_output, "-,")
      end
  end

  -- Print hex and printable characters, 32 per line
  local hex_index = 1
  local line_length = 32

  while hex_index <= #hex_output do
    -- Collect hex characters for the current line
    local line = {}
    for i = 1, line_length do
      if hex_index <= #hex_output then
        table.insert(line, hex_output[hex_index])
        hex_index = hex_index + 1
      end
    end

    -- Print the current line with hex values and printable characters
    print(table.concat(line, " "))
  end
end

function cql_varint_decode(x, pos, lim)
  local result = 0
  local shift = 0
  local b = 0
  local count = 0
  repeat
    b = string.byte(x, pos)
    if b == nil or count >= lim then
      return nil, nil
    end
    pos = pos + 1
    result = result | ((b & 0x7F) << shift)
    shift = shift + 7
    count = count + 1
  until b < 0x80
  result = cql_zigzag_decode(result)
  return result, pos
end

function cql_varint_decode_32(x, pos)
  -- at most 5 bytes
  x, pos = cql_varint_decode(x, pos, 5)
  return x, pos
end

function cql_varint_decode_64(x, pos)
  -- at most 10 bytes
  x, pos = cql_varint_decode(x, pos, 10)
  return x, pos
end

function cql_unpack_z(str, pos)
  local success, result, next_pos = pcall(string.unpack, "z", str, pos)
  if success then
    return result, next_pos
  else
    return nil, nil
  end
end

function cql_unpack_d(str, pos)
  local success, result, next_pos = pcall(string.unpack, "d", str, pos)
  if success then
    return result, next_pos
  else
    return nil, nil
  end
end

function cql_unpack_c(str, pos, size)
  local success, result, next_pos = pcall(string.unpack, "c" .. size, str, pos)
  if success then
    return result, next_pos
  else
    return nil, nil
  end
end

function cql_cursor_from_blob(C, C_types, C_fields, buffer)
  if C == nil then
    return -100
  end

  C._has_row_ = false

  if buffer == nil then
    return -101
  end

  if C_types == nil then
    return -102
  end

  if C_fields == nil then
    return -103
  end

  -- this will help us with missing fields, we have to assume that the buffer
  -- might be from the past or future and have different fields, we can
  -- handle a lot of these cases.
  cql_empty_cursor(C, C_types, C_fields)

  local pos = 1
  local types, pos = cql_unpack_z(buffer, pos)
  if types == nil then
    return -104
  end

  local nullable_count = 0
  local bool_count = 0
  local actual_count = #types
  local needed_count = #C_fields
  local code
  local type
  local chunk_size
  local i = 0
  local bit = false

  for i = 1, actual_count do
    code = string.byte(types, i)

    if code >= string.byte("a") then
      nullable_count = nullable_count + 1;
    end

    if code == CQL_ENCODED_TYPE_BOOL_NOTNULL or code == CQL_ENCODED_TYPE_BOOL then
      bool_count = bool_count + 1;
    end

    -- Extra fields do not have to match, the assumption is that this is a
    -- future version of the type talking to a past version.  The past version
    -- sees only what it expects to see.  However, we did have to compute the
    -- nullable_count and bool_count to get the bit vector size correct.
    if i <= needed_count then
      type = string.byte(C_types, i)

      if type ~= code then
        -- if the type doesn't match exactly we're still ok if the actual type
        -- is not nullable and the required type is nullable.
        if code + 32 ~= type then
          rc = sqlite3.TYPE_MISMATCH
          goto cql_error
        end
      end
    end
  end

  -- if we have too few fields we can use null fillers, this is the versioning
  -- policy, we will check that any missing fields are nullable.
  for i = actual_count +1, needed_count do
    local type = string.byte(C_types, i)
    if type < string.byte("a") then
      rc = sqlite3.TYPE_MISMATCH
      goto cql_error
    end
    i = i + 1
  end

  bytes = (nullable_count + bool_count + 7) // 8

  bits = {}
  for i = 1, bytes do
    bits[i] = string.byte(buffer, pos)
    pos = pos + 1
  end

  -- all the fields are already zeroed out, we only need to set the ones that
  -- are not null and not zero.
  nullable_index = 0
  bool_index = 0

  for i = 1, math.min(needed_count, actual_count) do
    field = C_fields[i]
    code = string.byte(types, i)
    if code == CQL_ENCODED_TYPE_BOOL_NOTNULL then
      bit = cql_getbit(bits, nullable_count + bool_index)
      if bit == nil then
        return -1
      end
      C[field] = bit
      bool_index = bool_index + 1
    elseif code == CQL_ENCODED_TYPE_BOOL then
      bit = cql_getbit(bits, nullable_index)
      if bit == nil then
        return -2
      end
      if bit then
        bit = cql_getbit(bits, nullable_count + bool_index)
        if bit == nil then
          return -3
        end
        C[field] = bit
      end
      bool_index = bool_index + 1
      nullable_index = nullable_index + 1
    elseif code == CQL_ENCODED_TYPE_INT_NOTNULL then
      C[field], pos = cql_varint_decode_32(buffer, pos)
      if pos == nil then
        return -4
      end
    elseif code == CQL_ENCODED_TYPE_INT then
      bit = cql_getbit(bits, nullable_index)
      if bit == nil then
        return -5
      end
      if bit then
        C[field], pos = cql_varint_decode_32(buffer, pos)
        if pos == nil then
          return -6
        end
      end
      nullable_index = nullable_index + 1
    elseif code == CQL_ENCODED_TYPE_LONG_NOTNULL then
      C[field], pos = cql_varint_decode_64(buffer, pos)
      if pos == nil then
        return -7
      end
    elseif code == CQL_ENCODED_TYPE_LONG then
      bit = cql_getbit(bits, nullable_index)
      if bit == nil then
        return -8
      end
      if bit then
        C[field], pos = cql_varint_decode_64(buffer, pos)
        if pos == nil then
          return -9
        end
      end
      nullable_index = nullable_index + 1
    elseif code == CQL_ENCODED_TYPE_DOUBLE_NOTNULL then
      C[field], pos = cql_unpack_d(buffer, pos)
      if pos == nil then
        return -10
      end
    elseif code == CQL_ENCODED_TYPE_DOUBLE then
      bit = cql_getbit(bits, nullable_index)
      if bit == nil then
        return -11
      end
      if bit then
        C[field], pos = cql_unpack_d(buffer, pos)
        if pos == nil then
          return -12
        end
      end
      nullable_index = nullable_index + 1
    elseif code == CQL_ENCODED_TYPE_STRING_NOTNULL then
      C[field], pos = cql_unpack_z(buffer, pos)
      if pos == nil then
        return -13
      end
    elseif code == CQL_ENCODED_TYPE_STRING then
      bit = cql_getbit(bits, nullable_index)
      if bit == nil then
        return -14
      end
      if bit then
        C[field], pos = cql_unpack_z(buffer, pos)
        if pos == nil then
          return -15
        end
      end
      nullable_index = nullable_index + 1
    elseif code == CQL_ENCODED_TYPE_BLOB_NOTNULL then
      chunk_size, pos = cql_varint_decode_32(buffer, pos)
      if pos == nil then
        return -16
      end
      C[field], pos = cql_unpack_c(buffer, pos, chunk_size)
      if pos == nil then
        return -17
      end
    elseif code == CQL_ENCODED_TYPE_BLOB then
      bit = cql_getbit(bits, nullable_index)
      if bit == nil then
        return -18
      end
      if bit then
        chunk_size, pos = cql_varint_decode_32(buffer, pos)
        if pos == nil then
          return -19
        end
        C[field], pos = cql_unpack_c(buffer, pos, chunk_size)
        if pos == nil then
          return -20
        end
      end
      nullable_index = nullable_index + 1
    end
  end

  C._has_row_ = true
  rc = sqlite3.OK

::cql_error::
  return rc
end
