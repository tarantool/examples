-- This file is required automatically by luatest.
-- Add common configuration here.

local fio = require('fio')
local t = require('luatest')

local helper = {}

helper.root = fio.dirname(fio.abspath(package.search('init')))
helper.datadir = fio.pathjoin(helper.root, 'tmp', 'db_test')
helper.server_command = fio.pathjoin(helper.root, 'init.lua')

helper.deepcopy = function(origin)
    local origin_type = type(origin)
    local copy
    if origin_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, origin, nil do
            copy[helper.deepcopy(orig_key)] = helper.deepcopy(orig_value)
        end
        setmetatable(copy, helper.deepcopy(getmetatable(origin)))
    else -- number, string, boolean, etc
        copy = origin
    end
    return copy
end

t.before_suite(function()
    fio.rmtree(helper.datadir)
    fio.mktree(helper.datadir)
end)

return helper
