#!/usr/bin/env tarantool

local param = ...

local ret = {obj = param, priority = 1, routing_key = 'input_key'}

return ret
