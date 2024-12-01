--[[
Copyright (c) Meta Platforms, Inc. and affiliates.

This source code is licensed under the MIT license found in the
LICENSE file in the root directory of this source tree.
--]]

-- TESTING METHODS --

function cql_normalize_bool_to_int(val)
  if val == nil then return nil end
  if val == false then return 0 end
  if val == true then return 1 end
  if val ~= 0 then return 1 end
  return 0
end

cql_required_val_type = {}

CQL_BLOB_MAGIC = 0x524d3030

function cql_serialize_key_blob(t)
  result = string.pack(">I8I4I4", t.rtype, t.magic, t.cols)

  i = 0
  cols = t.cols
  while i < cols
  do
    code = t["t"..i]
    val = t["v"..i]
    if code == CQL_BLOB_TYPE_BOOL or code == CQL_BLOB_TYPE_INT32 or code == CQL_BLOB_TYPE_INT64 then
       result = result..string.pack(">I1I8", code, val)
    elseif code == CQL_BLOB_TYPE_FLOAT then
        result = result..string.pack(">I1d", code, val)
    else
      -- CQL_BLOB_TYPE_STRING or t == CQL_BLOB_TYPE_BLOB then
      result = result..string.pack(">I1s4", code, val)
    end
    i = i + 1
  end
  return result;
end

function cql_deserialize_key_blob(b)
  t = {}
  -- check minimum size for the header
  if type(b) ~= 'string' or string.len(b) < 16 then
    return t
  end

  rtype, magic, cols, pos = string.unpack(">I8I4I4", b)
  t.rtype = rtype
  t.magic = magic
  t.cols = cols

  if magic ~= CQL_BLOB_MAGIC then
    return t
  end

  i = 0
  while i < cols
  do
    code, pos = string.unpack(">I1", b, pos)
    if code == CQL_BLOB_TYPE_BOOL or code == CQL_BLOB_TYPE_INT32 or code == CQL_BLOB_TYPE_INT64 then
      val, pos = string.unpack(">I8", b, pos)
    elseif code == CQL_BLOB_TYPE_FLOAT then
      val, pos = string.unpack(">d", b, pos)
    else
      val, pos = string.unpack(">s4", b, pos)
    end

    t["v"..i] = val
    t["t"..i] = code
    i = i + 1
  end

  return t
end

function cql_serialize_val_blob(t)
  result = string.pack(">I8I4I4", t.rtype, t.magic, t.cols)

  for k,v in pairs(t) do
    if string.sub(k, 1, 1) == 't'  then
      id = tonumber(string.sub(k, 2))
      code = v
      val = t["v"..id]
      if code == CQL_BLOB_TYPE_BOOL or code == CQL_BLOB_TYPE_INT32 or code == CQL_BLOB_TYPE_INT64 then
        result = result..string.pack(">I1>I8>I8", code, id, val)
      elseif code == CQL_BLOB_TYPE_FLOAT then
        result = result..string.pack(">I1>I8d", code, id, val)
      else
        -- CQL_BLOB_TYPE_STRING or t == CQL_BLOB_TYPE_BLOB then
        result = result..string.pack(">I1>I8s4", code, id, val)
      end
    end
  end

  return result;
end

function cql_deserialize_val_blob(b)
  t = {}
  -- check minimum size for the header
  if type(b) ~= 'string' or string.len(b) < 16 then
    return t
  end

  rtype, magic, cols, pos = string.unpack(">I8I4I4", b)
  t.rtype = rtype
  t.magic = magic
  t.cols = cols

  if magic ~= CQL_BLOB_MAGIC then
    return t
  end

  i = 0
  while i < cols
  do
    code, pos = string.unpack(">I1", b, pos)
    if code == CQL_BLOB_TYPE_BOOL or code == CQL_BLOB_TYPE_INT32 or code == CQL_BLOB_TYPE_INT64 then
      id, val, pos = string.unpack(">I8>I8", b, pos)
    elseif code == CQL_BLOB_TYPE_FLOAT then
      id, val, pos = string.unpack(">I8d", b, pos)
    else
      id, val, pos = string.unpack(">I8s4", b, pos)
    end

    t["v"..id] = val
    t["t"..id] = code
    i = i + 1
  end

  return t
end

function bcreatekey(context, rtype, ...)
  local args = {...}
  local i = 0
  local off = 1
  local t = {}

  t.magic = CQL_BLOB_MAGIC
  t.rtype = rtype
  t.cols = math.floor(#args / 2)

  -- if the record type is not numeric then exit
  if type(rtype) ~= 'number' then
    goto err_exit
  end

  -- if too few args then exit
  if #args == 0 then
    goto err_exit
  end

  -- if the parity of the arguments is wrong, exit
  if #args % 2 ~= 0 then
    goto err_exit
  end

  i = 1
  icol = 0
  while i + 1 <= #args
  do
    ctype = args[i+1]
    val = args[i]

    -- if the column type is not a number, exit
    if type(ctype) ~= 'number' then
      goto err_exit
    end

    -- if the column type is out of range, exit
    if ctype < CQL_BLOB_TYPE_BOOL or ctype >= CQL_BLOB_TYPE_ENTITY then
      goto err_exit
    end

    -- sanity check type of value against arg type
    if cql_required_val_type[ctype] ~= type(val) then
      goto err_exit
    end

    if ctype == CQL_BLOB_TYPE_BOOL then
      -- normalize booleans
     val = cql_normalize_bool_to_int(val)
    end

     t["t"..icol] = ctype
     t["v"..icol] = val
     i = i + 2
     icol = icol + 1
  end

  context:result_blob(cql_serialize_key_blob(t))
  goto done

::err_exit::
  context:result_null();

::done::
end

function bgetkey(context, b, i)
  local t = cql_deserialize_key_blob(b)
  if t.magic ~= CQL_BLOB_MAGIC or type(i) ~= 'number' then
    context:result_null();
  else
    context:result(t["v"..i])
  end
end

function bgetkey_type(context, b)
  local t = cql_deserialize_key_blob(b)
  if t.magic ~= CQL_BLOB_MAGIC then
    context:result_null();
  else
    context:result(t.rtype)
  end
end

function bupdatekey(context, b, ...)
  local args = {...}
  local i = 1
  local t = cql_deserialize_key_blob(b)
  local already_updated = {}

  if t.magic ~= CQL_BLOB_MAGIC then
    goto err_exit
  end

  cols = t.cols
  while i + 1 <= #args
  do
    local icol = args[i]
    if type(icol) ~= 'number' or icol < 0 or icol >= cols then
      goto err_exit
    end

    ctype = t["t"..icol]
    val = args[i+1]

    if already_updated[icol] ~= nil then
      goto err_exit
    end
    already_updated[icol] = 1

    -- sanity check type of value against arg type
    if cql_required_val_type[ctype] ~= type(val) then
      goto err_exit
    end

    if ctype == CQL_BLOB_TYPE_BOOL then
      val = cql_normalize_bool_to_int(val) -- normalize booleans
    end

    t["v"..icol] = val
    i = i + 2
  end
  context:result_blob(cql_serialize_key_blob(t))
  goto done

::err_exit::
  context:result_null();

::done::
end

function bcreateval(context, rtype, ...)
  local args = {...}
  local i = 0
  local off = 1
  local t = {}
  t.magic = CQL_BLOB_MAGIC
  t.rtype = rtype

  cols = 0

  -- if the record type is not numeric then exit
  if type(rtype) ~= 'number' then
    goto err_exit
  end

  -- if the parity of the arguments is wrong, exit
  if #args % 3 ~= 0 then
    goto err_exit
  end

  i = 1
  while i + 2 <= #args
  do
    ctype = args[i+2]
    val = args[i+1]
    id = args[i]

    -- if the column type is not a number, exit
    if type(ctype) ~= 'number' or type(id) ~= 'number' then
      goto err_exit
    end

    -- if the column type is out of range, exit
    if ctype < CQL_BLOB_TYPE_BOOL or ctype >= CQL_BLOB_TYPE_ENTITY then
      goto err_exit
    end

    -- sanity check type of value against arg type
    if val ~= nil and cql_required_val_type[ctype] ~= type(val) then
      goto err_exit
    end

    if ctype == CQL_BLOB_TYPE_BOOL then
      -- normalize booleans
     val = cql_normalize_bool_to_int(val)
    end

    if val ~= nil then
      t["t"..id] = ctype
      t["v"..id] = val
      cols = cols + 1
    end
    i = i + 3
  end

  t.cols = cols

  context:result_blob(cql_serialize_val_blob(t))
  goto done

::err_exit::
  context:result_null();

::done::
end
function bgetval(context, b, id)
  local t = cql_deserialize_val_blob(b)

  if t.magic ~= CQL_BLOB_MAGIC or type(id) ~= 'number' then
    context:result_null();
  else
    context:result(t["v"..id])
  end
end

function bgetval_type(context, b)
  local t = cql_deserialize_val_blob(b)

  if t.magic ~= CQL_BLOB_MAGIC then
    context:result_null();
  else
    context:result(t.rtype)
  end
end

function bupdateval(context, b, ...)
  local args = {...}
  local i = 1
  local already_updated = {}

  local t = cql_deserialize_val_blob(b)

  if t.magic ~= CQL_BLOB_MAGIC then
    goto err_exit
  end

  cols = t.cols
  while i + 2 <= #args
  do
    local id = args[i]
    local val = args[i+1]
    local newtype = args[i+2]

    if already_updated[id] ~= nil then
      goto err_exit
    end

    already_updated[id] = 1

    if type(id) ~= 'number' or type(newtype) ~= 'number' then
      goto err_exit
    end

    stored_type = t["t"..id]

    -- if there is an existing type then it must match
    if stored_type ~= nil and stored_type ~= newtype then
      goto err_exit
    end

    -- sanity check type of value against arg type
    if val ~= nil and cql_required_val_type[newtype] ~= type(val) then
      goto err_exit
    end

    if ctype == CQL_BLOB_TYPE_BOOL then
      val = cql_normalize_bool_to_int(val) -- normalize booleans
    end

    if stored_type == nil and val ~= nil then
      cols = cols + 1
      t["t"..id] = newtype
    elseif stored_type ~= nil and val == nil then
      cols = cols - 1
      t["t"..id] = nil
    end

    t["v"..id] = val

    i = i + 3
  end
  t.cols = cols

  context:result_blob(cql_serialize_val_blob(t))
  goto done

::err_exit::
  context:result_null();

::done::
end


function rscount(context, rsid)
  local rs = cql_get_aux_value_for_id(rsid)
  context:result_int(#rs)
end

function rscol(context, rsid, rownum, colnum)
  local rs = cql_get_aux_value_for_id(rsid)
  local row = rs[rownum+1]

  -- columns are not in order so we just hard code the order for the test
  if colnum == 0 then
    k = "v"
  else
    k = "vsq"
  end

  result = row[k]
  context:result(result)
end

function _cql_init_extensions(db)
  -- defer initialization until after these constants are defined in cqlrt.lua
  cql_required_val_type = {
    [CQL_BLOB_TYPE_BOOL] = 'number',
    [CQL_BLOB_TYPE_INT32] = 'number',
    [CQL_BLOB_TYPE_INT64] = 'number',
    [CQL_BLOB_TYPE_FLOAT] = 'number',
    [CQL_BLOB_TYPE_STRING] = 'string',
    [CQL_BLOB_TYPE_BLOB] = 'string'
  }

  db:create_function("rscount", 1, rscount)
  db:create_function("rscol", 3, rscol)
  db:create_function("bupdateval", -1, bupdateval)
  db:create_function("bupdatekey", -1, bupdatekey)
  db:create_function("bcreateval", -1, bcreateval)
  db:create_function("bcreatekey", -1, bcreatekey)
  db:create_function("bgetval_type", 1, bgetval_type)
  db:create_function("bgetkey_type", 1, bgetkey_type)
  db:create_function("bgetval", 2, bgetval)
  db:create_function("bgetkey", 2, bgetkey)
  return sqlite3.OK
end

function get_outstanding_refs()
  return 0
end

function string_from_blob(str)
  return str
end

function blob_from_string(blob)
  return blob
end

function run_test_math(int1)
   return int1 * 7, int1 * 5
end

function string_create()
  return "Hello, world."
end

function set_create()
  return {}
end

function set_contains(s, k)
  return s[k] ~= nil
end

function set_add(s, k)
  if s[k] ~= nil then
    return false
  end

  s[k] = 1
  return true
end

function cql_invariant(x)
 if x == false or x == 0 then
    print("invariant failed")
    force_error_exit()
 end
end

function some_integers_fetch(a,b,c)
  return some_integers_fetch_results(a,b,c)
end

function exit(code)
  print("exit code", code)
end

function take_bool(x,y)
  if x ~= y then
    print("invariant failed")
    force_error_exit()
  end
end

function take_bool_not_null(x,y)
  if x ~= y then
    print("invariant failed")
    force_error_exit()
  end
end

function create_truncated_blob(b, new_size)
  if new_size >= #b then
    print("new size is not smaller than old size")
    force_error_exit()
  end
  return string.sub(b, 1, new_size)
end

rand_state = 0

-- to ensure we can get the same series again (this is public)
function rand_reset()
  rand_state = 0
end

-- This random number generator doesn't have to be very good
-- but I can't use anything that looks standard because of who
-- knows what copyright issues I might face for daring to use the same
-- integers in linear congruence math. So for this lame thing I picked my
-- own constants out of thin air and I have no idea if they are any good
-- but they are my own and really we just don't care that much.
function seriously_lousy_rand()
  rand_state = (rand_state * 1302475243 + 21493) & 0x7fffffff
  return rand_state;
end

-- corrupt the blob
function corrupt_blob_with_invalid_shenanigans(b)
  local size = cql_get_blob_size(b);

  bytes = {}
  for i = 1, #b do
    bytes[i] = string.byte(b, i)
  end

  for i = 1, 20 do
     index = seriously_lousy_rand() % size
     byte = seriously_lousy_rand() & 0xff

     -- smash
     bytes[index] = byte;
  end
  return string.char(table.unpack(bytes))
end
