--[[
Copyright (c) Meta Platforms, Inc. and affiliates.

This source code is licensed under the MIT license found in the
LICENSE file in the root directory of this source tree.
--]]

-- TESTING METHODS --

-- this is better done with string.pack but this is human
-- readable and therefore easier to debug and it works just
-- as well for the test case

function str_unpack(str)
  local data = {}
  for w in str:gmatch("([^,]+)") do table.insert(data, w) end
  for i = 1, 4
  do
    if data[i] == nil then data[i] = "0" end
    data[i] = tonumber(data[i])
  end

  return data[1], data[2], data[3], data[4]
end

function str_pack(a,b,c,d)
  return tostring(a)..","..tostring(b)..","..tostring(c)..","..tostring(d)
end

-- this is a standard serializer courtesy of From: Tony Finch <dot@...>
-- http://lua-users.org/lists/lua-l/2009-11/msg00533.html
-- (publicly posted as a code sample)
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

function bcreateval(context, t, ...)
  local vals = {0, 0, 0}
  local args = {...}
  local i = 0
  while i + 3 <= #args
  do
     local off = args[i+1]
     local val = args[i+2]
     vals[off+1] = val
     i = i  + 3
  end
  local r = str_pack(t, vals[1], vals[2], vals[3])
  context:result_blob(r);
end

function bupdateval(context, b, ...)
  local t, v1, v2, v3
  t, v1, v2, v3 = str_unpack(b)
  local vals = {v1, v2, v3}
  local args = {...}
  local i = 0
  while i + 3 <= #args
  do
     local off = args[i+1]
     local val = args[i+2]
     vals[off+1] = val
     i = i  + 3
  end
  local r = str_pack(t, vals[1], vals[2], vals[3])
  context:result_blob(r)
end

function cql_normalize_bool_to_int(val)
  if val == nil then return nil end
  if val == false then return 0 end
  if val == true then return 1 end
  if val ~= 0 then return 1 end
  return 0
end

function bcreatekey(context, rtype, ...)
  local args = {...}
  local i = 0
  local off = 1
  local t = {}
  t.rtype = rtype
  t.cols = math.floor(#args / 2)

  i = 1
  icol = 0
  while i + 1 <= #args
  do
    ctype = args[i+1]
    val = args[i]

    if ctype == CQL_BLOB_TYPE_BOOL then
      val = cql_normalize_bool_to_int(val) -- normalize booleans
    end

     t["t"..icol] = ctype
     t["v"..icol] = val
     i = i + 2
     icol = icol + 1
  end

  local r = serialize(t)
  context:result_blob(r)
end

function bgetkey(context, b, i)
 local t = load(b)()
 context:result(t["v"..i])
end

function bgetkey_type(context, b)
 local t = load(b)()
 context:result(t.rtype)
end

function bupdatekey(context, b, ...)
  local args = {...}
  local t = load(b)()
  local i = 1
  while i + 1 <= #args
  do
    local icol = args[i]
    ctype = t["t"..icol] 
    val = args[i+1]

    if ctype == CQL_BLOB_TYPE_BOOL then
      val = cql_normalize_bool_to_int(val) -- normalize booleans
    end

    t["v"..icol] = val
    i = i + 2
  end
  local r = serialize(t)
  context:result_blob(r)
end

function bgetval_type(context, b)
  t = str_unpack(b)
  -- note: result(t) allows int64 results as well as int
  context:result(t)
end

function bgetval(context, b, offs)
  local t, v1, v2, v3
  t, v1, v2, v3 = str_unpack(b)
  local r = 0
  if offs == 0 then r = v1 end
  if offs == 1 then r = v2 end
  if offs == 2 then r = v3 end
  -- note: result(t) allows int64 results as well as int
  context:result(r)
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
