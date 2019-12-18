local t = require('luatest')

local shared = require('test.helper')

local helper = {shared = shared}

t.before_suite(function() box.cfg({work_dir = shared.datadir}) end)

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

return helper
