#!/usr/bin/env tarantool

local param = ...

param.obj.name = param.obj.first_name .. ' ' .. param.obj.last_name
param.obj.first_name = nil
param.obj.last_name = nil

param.routing_key = "account_key"

return param
