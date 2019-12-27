local t = require('luatest')
local g = t.group('integration_api')

local helper = require('test.helper.integration')
local cluster = helper.cluster
local deepcopy = helper.shared.deepcopy

local mysql = require('mysql')

local test_profile = {
    profile_id = 1, 
    first_name = 'Petr',
    sur_name = 'Petrov',
    patronymic = 'Ivanovich',
    msgs_count = 110,
    service_info = 'admin'
}

local user_password = 'qwerty'

g.test_sample = function()
    local server = cluster.main_server
    local response = server:http_request('post', '/admin/api', {json = {query = '{}'}})
    t.assert_equals(response.json, {data = {}})
    t.assert_equals(server.net_box:eval('return box.cfg.memtx_dir'), server.workdir)
end

g.test_on_get_not_found = function()
    helper.assert_http_json_request('get', '/profile/1', {password = user_password}, {body = {info = "Profile not found"}, status = 404})
end

g.test_on_post_ok = function ()
    local user_with_password = deepcopy(test_profile)
    user_with_password.password = user_password
    helper.assert_http_json_request('post', '/profile', user_with_password, {status=201})
end

g.test_on_post_conflict = function()
    local user_with_password = deepcopy(test_profile)
    user_with_password.password = user_password
    helper.assert_http_json_request('post', '/profile', user_with_password, {body = {info = "Profile already exist"}, status=409})
end

g.test_on_get_ok = function ()
    helper.assert_http_json_request('get', '/profile/1', {password = user_password}, {body = test_profile, status = 200})
end

g.test_on_get_unauthorized = function()
    helper.assert_http_json_request('get', '/profile/1', {password = 'passwd'}, {body = {info = "Unauthorized"}, status = 401})
end

g.test_on_put_not_found = function()
    helper.assert_http_json_request('put', '/profile/2', {password = user_password, changes ={msgs_count = 115}},
    {body = {info = "Profile not found"}, status = 404})
end

g.test_on_put_unauthorized = function()
    helper.assert_http_json_request('put', '/profile/1', {password = 'passwd', changes = {msgs_count = 115}}, 
    {body = {info = "Unauthorized"}, status = 401})
end

g.test_on_put_ok = function()
    local changed_profile = deepcopy(test_profile)
    changed_profile.msgs_count = 115
    helper.assert_http_json_request('put', '/profile/1', {password = user_password , changes = {msgs_count = 115}}, {body = changed_profile, status = 200})
end

g.test_on_delete_not_found = function ()
    helper.assert_http_json_request('delete', '/profile/2', {password = user_password}, {body = {info = "Profile not found"}, status = 404})
end

g.test_on_delete_unauthorized = function ()
    helper.assert_http_json_request('delete', '/profile/1', {password = 'passwd'}, {body = {info = "Unauthorized"}, status = 401})
end

g.test_on_delete_ok = function()
    helper.assert_http_json_request('delete', '/profile/1', {password = user_password}, {body = {info = "Deleted"}, status = 200})
end

g.before_all = function ()
    local connection = mysql.connect({
        host='127.0.0.1', 
        user='root', 
        password='password', 
        db='profile_storage',
    })
    connection:execute('DELETE FROM user_profile')
    connection:close()
end
