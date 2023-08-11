--[[
Copyright (c) Meta Platforms, Inc. and affiliates.

This source code is licensed under the MIT license found in the
LICENSE file in the root directory of this source tree.
--]]

-- TESTING METHODS --

-- this is a standard serializer courtesy of Tony Finch
-- http://lua-users.org/lists/lua-l/2009-11/msg00533.html
-- it was publicly posted as a code sample
--
local szt = {}

local function char(c) return ("\\%3d"):format(c:byte()) end
local function szstr(s) return ('"%s"'):format(s:gsub("[^ !#-~]", char)) end
local function szfun(f) return "loadstring"..szstr(string.dump(f)) end
local function szany(...) return szt[type(...)](...) end

local function sztbl(t,code,var)
  for k,v in pairs(t) do
    local ks = szany(k,code,var)
    local vs = szany(v,code,var)
    code[#code+1] = ("%s[%s]=%s"):format(var[t],ks,vs)
  end
  return "{}"
end

local function memo(sz)
  return function(d,code,var)
    if var[d] == nil then
      var[1] = var[1] + 1
      var[d] = ("_[%d]"):format(var[1])
      local index = #code+1
      code[index] = "" -- reserve place during recursion
      code[index] = ("%s=%s"):format(var[d],sz(d,code,var))
    end
    return var[d]
  end
end

szt["nil"]      = tostring
szt["boolean"]  = tostring
szt["number"]   = tostring
szt["string"]   = szstr
szt["function"] = memo(szfun)
szt["table"]    = memo(sztbl)

function serialize(d)
  local code = { "local _ = {}" }
  local value = szany(d,code,{0})
  code[#code+1] = "return "..value
  if #code == 2 then return code[2]
  else return table.concat(code, "\n")
  end
end

function cql_normalize_bool_to_int(val)
  if val == nil then return nil end
  if val == false then return 0 end
  if val == true then return 1 end
  if val ~= 0 then return 1 end
  return 0
end

cql_required_val_type = {}

CQL_BLOB_MAGIC = 0x524d3030

function cql_load_blob(b)
  if type(b) ~= "string" then
    return {}
  end

  -- note this is not safe generally, it's ok for test code but
  -- you want something that can't be hijacked in real code
  local f = load(b)

  if f == nil then
    return {}
  end

  return f();
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

  context:result_blob(serialize(t))
  goto done

::err_exit::
  context:result_null();

::done::
end

function bgetkey(context, b, i)
  local t = cql_load_blob(b)
  if t.magic ~= CQL_BLOB_MAGIC or type(i) ~= 'number' then
    context:result_null();
  else
    context:result(t["v"..i])
  end
end

function bgetkey_type(context, b)
  local t = cql_load_blob(b)

  if t.magic ~= CQL_BLOB_MAGIC then
    context:result_null();
  else
    context:result(t.rtype)
  end
end

function bupdatekey(context, b, ...)
  local args = {...}
  local i = 1
  local t = cql_load_blob(b)
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
  context:result_blob(serialize(t))
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
  t.cols = math.floor(#args / 3)

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

     t["t"..id] = ctype
     t["v"..id] = val
     i = i + 3
  end

  context:result_blob(serialize(t))
  goto done

::err_exit::
  context:result_null();

::done::
end
function bgetval(context, b, id)
  local t = cql_load_blob(b)

  if t.magic ~= CQL_BLOB_MAGIC or type(id) ~= 'number' then
    context:result_null();
  else
    context:result(t["v"..id])
  end
end

function bgetval_type(context, b)
  local t = cql_load_blob(b)

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

  local t = cql_load_blob(b)

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

    t["t"..id] = newtype
    t["v"..id] = val
    i = i + 3
  end

  context:result_blob(serialize(t))
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
