#!/usr/bin/env tarantool

local param = ...

if param.obj.id ~= nil then
  param.routing_key = "account_key"
  return param
end

param.routing_key = "unknown_input"
return param
