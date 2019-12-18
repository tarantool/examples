local t = require('luatest')
local g = t.group('unit_lru_cache')
local lru_cache = require('app.lru_cache')

require('test.helper.unit')

local cache = {}

g.test_new = function()
    cache = lru_cache.new(1)
    t.assert_equals(type(cache), 'table')
    t.assert_equals(cache:is_empty(), true)
end

g.test_set_ok = function()
    local stale_key = cache:set('x', true)
    t.assert_equals(stale_key, nil)
    t.assert_equals(cache:is_empty(), false)
    t.assert_equals(cache:filled(), 1)
end

g.test_get_ok = function()
    local value = cache:get('x')
    t.assert_equals(value, true)
    t.assert_equals(cache:is_empty(), false)
    t.assert_equals(cache:filled(), 1)
end

g.test_is_full = function()
    t.assert_equals(cache:is_full(), true)
    local stale_key = cache:set('y', 42)
    t.assert_equals(stale_key, 'x')
    t.assert_equals(cache:is_full(), true)
end

g.test_get_not_found = function()
    local value = cache:get('x')
    t.assert_equals(value, nil)
end

g.test_remove_ok = function()
    local ok = cache:remove('y')
    t.assert_equals(ok, true)
    t.assert_equals(cache:get('y'), nil)
    t.assert_equals(cache:is_empty(), true)
end

g.test_remove_not_found = function()
    local ok = cache:remove('y')
    t.assert_equals(ok, false)
end