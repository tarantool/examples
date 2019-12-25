local t = require('luatest')
local g = t.group('unit_storage_utils')
local helper = require('test.helper.unit')

require('test.helper.unit')


local storage = require('app.roles.storage') 
local utils = storage.utils
local deepcopy = helper.shared.deepcopy

local test_profile = {
    profile_id = 1,
    bucket_id = 1,
    first_name = 'Petr',
    sur_name = 'Petrov',
    patronymic = 'Ivanovich',
    msgs_count = 100,
    service_info = 'admin'
}

g.test_sample = function()
    t.assert_equals(type(box.cfg), 'table')
    
end

g.test_profile_get_not_found = function()
    t.assert_equals(utils.profile_get(1), nil)
end

g.test_profile_get_found = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    local no_bucket_profile = deepcopy(test_profile)
    no_bucket_profile.bucket_id = nil
    t.assert_equals(utils.profile_get(1), no_bucket_profile)
end

g.test_profile_add_ok = function()
    t.assert_equals(utils.profile_add(deepcopy(test_profile)), true)
    t.assert_equals(box.space.profile:get(1), box.space.profile:frommap(test_profile))
end

g.test_profile_add_conflict = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    t.assert_equals(utils.profile_add(deepcopy(test_profile)), false)
end

g.test_profile_update_ok = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))

    local changes = {
        msgs_count = 333,
        first_name = "Ivan"
    }

    local updated_profile = deepcopy(test_profile)
    updated_profile.msgs_count = changes.msgs_count
    updated_profile.first_name = changes.first_name

    local no_bucket_profile = deepcopy(updated_profile)
    no_bucket_profile.bucket_id = nil

    t.assert_equals(utils.profile_update(1, changes), no_bucket_profile)
    t.assert_equals(box.space.profile:get(1), box.space.profile:frommap(updated_profile))
end

g.test_profile_update_not_found = function()
    t.assert_equals(utils.profile_update(1, {msgs_count = 111}), nil)
end

g.test_profile_delete_ok = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    t.assert_equals(utils.profile_delete(1), true)
    t.assert_equals(box.space.profile:get(1), nil, 'tuple must be deleted from space')
end

g.test_profile_delete_not_found = function()
    t.assert_equals(utils.profile_delete(1), false)
end

g.before_all(function()
    storage.init({is_master = true})
end)

g.before_each(function ()
    box.space.profile:truncate()
end)
