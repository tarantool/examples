local t = require('luatest')
local g = t.group('unit_storage_utils')
local helper = require('test.helper.unit')

require('test.helper.unit')


local storage = require('app.roles.storage')
local utils = storage.utils
local deepcopy = helper.shared.deepcopy
local auth = require('app.auth')

local test_profile = {
    profile_id = 1,
    bucket_id = 1,
    first_name = 'Petr',
    sur_name = 'Petrov',
    patronymic = 'Ivanovich',
    msgs_count = 100,
    service_info = 'admin'
}

local test_profile_no_shadow = deepcopy(test_profile)
test_profile_no_shadow.bucket_id = nil

local profile_password = 'qwerty'

local password_data = auth.create_password(profile_password)
test_profile.shadow = password_data.shadow
test_profile.salt = password_data.salt

g.test_sample = function()
    t.assert_equals(type(box.cfg), 'table')
    
end

g.test_profile_get_not_found = function()
    local res = utils.profile_get(1, profile_password)
    res.error = res.error.err
    t.assert_equals(res, {profile = nil, error = "Profile not found"})
end

g.test_profile_get_found = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    t.assert_equals(utils.profile_get(1, profile_password), {profile = test_profile_no_shadow, error = nil})
end

g.test_profile_get_unauthorized = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    local res = utils.profile_get(1, 'wrong_password')
    res.error = res.error.err
    t.assert_equals(res, {profile = nil, error = "Unauthorized"})
end

g.test_profile_add_ok = function()
    local to_insert = deepcopy(test_profile)
    to_insert.password = profile_password
    t.assert_equals(utils.profile_add(to_insert), {ok = true})
    to_insert.password = nil
    local from_space = box.space.profile:get(1)
    to_insert.shadow = from_space.shadow
    to_insert.salt = from_space.salt;
    t.assert_equals(from_space, box.space.profile:frommap(to_insert))
    t.assert_equals(auth.check_password(from_space, profile_password), true)
end

g.test_profile_add_conflict = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    local res = utils.profile_add(test_profile)
    res.error = res.error.err
    t.assert_equals(res, {ok = false, error = "Profile already exist"})
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
    local updated_no_shadow = deepcopy(test_profile_no_shadow)
    updated_no_shadow.msgs_count = changes.msgs_count
    updated_no_shadow.first_name = changes.first_name

    t.assert_equals(utils.profile_update(1, profile_password, changes), {profile = updated_no_shadow})
    t.assert_equals(box.space.profile:get(1), box.space.profile:frommap(updated_profile))
end

g.test_profile_update_not_found = function()
    local res = utils.profile_update(1, profile_password,{msgs_count = 111})
    res.error = res.error.err
    t.assert_equals(res, {profile = nil, error = res.error})
end

g.test_profile_update_unauthorized = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    local res = utils.profile_update(1, 'wrong_password', {msgs_count = 200})
    res.error = res.error.err
    t.assert_equals(res, {profile = nil, error = "Unauthorized"})
end

g.test_profile_update_password = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    local new_password = 'password'
    local res = utils.profile_update(1, profile_password, {password = new_password})
    t.assert_equals(res,{profile = test_profile_no_shadow})
    local profile = box.space.profile:get(1)
    t.assert_equals(auth.check_password(profile, new_password), true, 'incorrect shadow using profile salt')
end

g.test_profile_delete_ok = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    t.assert_equals(utils.profile_delete(1, profile_password), {ok = true})
    t.assert_equals(box.space.profile:get(1), nil, 'tuple must be deleted from space')
end

g.test_profile_delete_not_found = function()
    local res = utils.profile_delete(1, profile_password)
    res.error = res.error.err
    t.assert_equals(res, {ok = false, error = "Profile not found"})
end

g.test_profile_delete_unauthorized = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    local res = utils.profile_delete(1, 'wrong_password')
    res.error = res.error.err
    t.assert_equals(res, {ok = false, error = "Unauthorized"})
end

g.before_all(function()
    storage.init({is_master = true})
end)

g.before_each(function ()
    box.space.profile:truncate()
end)
