local t = require('luatest')
local g = t.group('unit_storage_utils')
local helper = require('test.helper.unit')

require('test.helper.unit')

local mock = require('test.mocks.mysql_handlers_mock')
package.loaded['app.mysql_handlers'] = mock

local storage = require('app.roles.storage')
local utils = storage.utils

g.test_sample = function()
    t.assert_equals(type(box.cfg), 'table')
end

g.test_profile_get_not_found = function()
    mock.set_retvalue(nil)
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_get(10), nil)
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_get_found_in_base = function()
    local profile = {
        profile_id = 2,
        bucket_id = 1, 
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 100,
        service_info = 'admin'
    }
    local profile_no_bucket = helper.deepcopy(profile)
    profile_no_bucket.bucket_id = nil
    mock.set_retvalue(helper.deepcopy(profile))
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_get(2), profile_no_bucket)
    t.assert_equals(box.space.profile:get(2), box.space.profile:frommap(profile))
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_get_found_in_cache = function ()
    mock.set_retvalue(nil)
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_get(2), {
        profile_id = 2, 
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 100,
        service_info = 'admin'
    })
    t.assert_equals(mock.calls_count(), previous_calls, 'mysql must not be called if key is in cache')
end

g.test_profile_add_ok = function()
    local profile = {
        profile_id = 1,
        bucket_id = 1, 
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 100,
        service_info = 'admin'
    }
    mock.set_retvalue(true)
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_add(helper.deepcopy(profile)), true)
    t.assert_equals(box.space.profile:get(1), box.space.profile:frommap(profile))
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_add_conflict_in_cache = function()
    local profile = {
        profile_id = 1,
        bucket_id = 1, 
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 100,
        service_info = 'admin'
    }
    mock.set_retvalue(false)
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_add(helper.deepcopy(profile)), false)
    t.assert_equals(mock.calls_count(), previous_calls, 'mysql must not be called if key is in cache')
end

g.test_profile_add_conflict_in_base = function()
    local profile = {
        profile_id = 10,
        bucket_id = 1, 
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 100,
        service_info = 'admin'
    }
    mock.set_retvalue(false)
    local previous_calls = mock:calls_count()
    t.assert_equals(utils.profile_add(helper.deepcopy(profile)), false)
    t.assert_equals(mock:calls_count(), previous_calls + 1 , 'mysql myst be called once')
end

g.test_profile_update_exists_in_base = function()
    local profile = {
        profile_id = 10,
        bucket_id = 1, 
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 100,
        service_info = 'admin'
    }
    local new_profile = {
        msgs_count = 100
    }

    mock.set_retvalue(helper.deepcopy(profile))
    local previous_calls = mock.calls_count()
    local profile_no_bucket = helper.deepcopy(profile)
    profile_no_bucket.bucket_id = nil
    t.assert_equals(utils.profile_update(10, new_profile), profile_no_bucket)
    t.assert_equals(box.space.profile:get(10), box.space.profile:frommap(profile))
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_update_exists_in_box = function()
    local profile = {
        profile_id = 10,
        bucket_id = 1,
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 322,
        service_info = 'admin'
    }
    local new_profile = {
        msgs_count = 322
    }

    mock.set_retvalue(helper.deepcopy(profile))
    local previous_calls = mock.calls_count()
    local profile_no_bucket = helper.deepcopy(profile)
    profile_no_bucket.bucket_id = nil
    t.assert_equals(utils.profile_update(10, new_profile), profile_no_bucket)
    t.assert_equals(box.space.profile:get(10), box.space.profile:frommap(profile))
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_update_not_found = function()
    mock.set_retvalue(nil)
    local previous_calls = mock:calls_count()
    t.assert_equals(utils.profile_update(12,{msgs_count = 255}), nil)
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_delete_ok = function()
    mock.set_retvalue(true)
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_delete(10), true)
    t.assert_equals(box.space.profile:get(10), nil,  'tuple must be deleted from space')
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_delete_not_found = function()
    mock.set_retvalue(false)
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_delete(10), false)
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.before_all(function()
    -- Выполним инициализацию модуля, чтобы создались экземпляры кэша и заглушки подключения к базе
    storage.init({is_master=true})
end)