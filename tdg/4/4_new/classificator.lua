#!/usr/bin/env tarantool

local param = ...

if param.obj.id ~= nil then
  param.routing_key = "add_person"
  return param
end

param.routing_key = "unknown_type"
return param
