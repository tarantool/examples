local t = require('luatest')
local g = t.group('unit_double_linked_list')
local linked_list = require('app.double_linked_list')

require('test.helper.unit')

g.test_new = function()
    local list = linked_list.new(2)

    t.assert_equals(type(list), 'table')
    t.assert_equals(list:is_empty(), true)
end

g.test_push_pop_ok = function()
    local list = linked_list.new(1)

    list:push(1)
    
    t.assert_equals(list:is_empty(), false)
    t.assert_equals(list:is_full(), true)
    t.assert_equals(list:pop(), 1)
    t.assert_equals(list:is_empty(), true)
end

g.test_push_pop_fail = function()
    local list = linked_list.new(2)

    list:push(1)
    list:push(2)
    local item, err = list:push(3)

    t.assert_equals(item, nil)
    t.assert_equals(err, 'List is full')

    list:pop()
    list:pop()
    local payload, err = list:pop()

    t.assert_equals(payload, nil)
    t.assert_equals(err, 'List is empty')
end

g.test_insert_remove_ok = function()
    local list = linked_list.new(3)

    local item1 = list:insert(1, nil)
    local item2 = list:insert(2, nil)
    local item3 = list:insert(3, item2)

    t.assert_equals(list:is_full(), true)
    t.assert_equals(list:remove(item1), 1)
    t.assert_equals(list:remove(item2), 2)
    t.assert_equals(list:pop(), 3)
end

g.test_insert_remove_fail = function()
    local list = linked_list.new(2)

    local item1 = list:insert(1, nil)
    local item2 = list:insert(2, nil)
    local item, err = list:insert(3, item2)

    t.assert_equals(item, nil)
    t.assert_equals(err, 'List is full')

    list:remove(item2)
    list:remove(item1)

    local payload, err = list:remove(item2)
    
    t.assert_equals(payload, nil)
    t.assert_equals(err, 'List is empty')

    item, err = list:insert(1, item1)

    t.assert_equals(item, nil)
    t.assert_equals(err, 'After is invalid')
end

g.test_clear = function()
    local list = linked_list.new(5)

    for i = 0, 5, 1 do
        list:push(i)
    end

    list:clear()

    t.assert_equals(list:is_empty(), true)

    for i = 5, 1, -1 do
        list:push(i)
    end

    t.assert_equals(list:pop(), 5)
end

