local fio = require('fio')
local t = require('luatest')
local g = t.group('simple_cache_integration')

local cartridge_helpers = require('cartridge.test-helpers')
local shared = require('test.helper')

local function assert_http_request(method, path, json, expect)
	local response = g.cluster.main_server:http_request(method, path, {json = json, raise = false})
	t.assert_equals(response.json['info'], expect.info)
	t.assert_equals(response.status, expect.status)
end

g.before_all(function() 

	g.cluster = cartridge_helpers.Cluster:new({
	    server_command = shared.server_command,
	    datadir = shared.datadir,
	    use_vshard = true,
	    replicasets = {
	        {
	            alias = 'api',
	            uuid = cartridge_helpers.uuid('a'),
	            roles = {'api'},
	            servers = {{ instance_uuid = cartridge_helpers.uuid('a', 1),
	            			advertise_port = 13301,
	            			http_port = 8081 
	            }},
	        },
		{
	            alias = 'storage',
	            uuid = cartridge_helpers.uuid('b'),
	            roles = {'simple_cache'},
	            servers = {{ instance_uuid = cartridge_helpers.uuid('b', 1),
	            			advertise_port = 13302,
	            			http_port = 8082 
	            }},
	        },
	    },
	})

	g.cluster:start()

end)

g.test_account_delete = function()

	assert_http_request('delete', '/storage/login', 
						nil, 
						{info = "Account not found", status = 404})
	
	assert_http_request('post', '/storage/create', 
						{login = "login1", name = "name", password = "1234", email =  "login@mail.com", data = "data"}, 
						{info = "Account successfully created", status = 201})
	
	assert_http_request('post', '/storage/create', 
						{login = "login2", name = "name", password = "1234", email =  "login@mail.com", data = "data"}, 
						{info = "Account successfully created", status = 201})
	
	assert_http_request('post', '/storage/create', 
						{login = "login1", name = "name", password = "1234", email =  "login@mail.com", data = "data"}, 
						{info = "Account with such login exists", status = 409})
	
	assert_http_request('delete', '/storage/login1', 
						nil, 
						{info = "Account deleted", status = 200})
	
	assert_http_request('delete', '/storage/login1', 
						nil, 
						{info = "Account not found", status = 404})
	
	assert_http_request('post', '/storage/create', 
						{login = "login2", name = "name", password = "1234", email =  "login@mail.com", data = "data"}, 
						{info = "Account with such login exists", status = 409})

end

g.test_account_add = function()

	assert_http_request('post', '/storage/create', 
						{login = "login1", name = "name", password = "1234", email =  "login@mail.com", data = "data"}, 
						{info = "Account successfully created", status = 201})
	
	assert_http_request('post', '/storage/create', 
						{login = "login1", name = "name", password = "1234", email =  "login@mail.com", data = "data"}, 
						{info = "Account with such login exists", status = 409})

	assert_http_request('post', '/storage/create', 
						{login = "login2", name = "name", password = "1234", email =  "login@mail.com", data = "data"}, 
						{info = "Account successfully created", status = 201})

	assert_http_request('post', '/storage/create', 
						{login = "login2", name = "name", password = "1234", email =  "login@mail.com", data = "data"}, 
						{info = "Account with such login exists", status = 409})

end

g.test_account_sign_out = function()

	assert_http_request('put', '/storage/login1/sign_out', 
						nil,
						{info = "Account not found", status = 404})

	assert_http_request('post', '/storage/create', 
						{login = "login1", name = "name1", password = "1", email =  "login1@mail.com", data = "data1"}, 
						{info = "Account successfully created", status = 201})


	assert_http_request('post', '/storage/create', 
						{login = "login2", name = "name2", password = "2", email =  "login2@mail.com", data = "data2"},
						{info = "Account successfully created", status = 201})

	assert_http_request('put', '/storage/login1/sign_out', 
						nil,
						{info = "Success", status = 200})

end

g.test_account_sign_in = function()
	
	assert_http_request('post', '/storage/create', 
						{login = "login1", name = "name1", password = "1", email =  "login1@mail.com", data = "data1"}, 
						{info = "Account successfully created", status = 201})

	assert_http_request('post', '/storage/create', 
						{login = "login2", name = "name2", password = "2", email =  "login2@mail.com", data = "data2"},
						{info = "Account successfully created", status = 201})

	assert_http_request('put', '/storage/login1/sign_out', 
						nil,
						{info = "Success", status = 200})

	assert_http_request('put', '/storage/login2/sign_out', 
						nil,
						{info = "Success", status = 200})

	assert_http_request('get', '/storage/login1/name', 
						nil,
						{info = "Sign in first. Session is down", status = 401})

	assert_http_request('get', '/storage/login2/name', 
						nil,
						{info = "Sign in first. Session is down", status = 401})

	assert_http_request('put', '/storage/login1/sign_in', 
						{password = "1"},
						{info = "Accepted", status = 202})

	assert_http_request('get', '/storage/login1/name', 
						nil,
						{info = "name1", status = 200})

	assert_http_request('get', '/storage/login2/name', 
						nil,
						{info = "Sign in first. Session is down", status = 401})

end

g.test_account_get = function()

	assert_http_request('post', '/storage/create', 
						{login = "login1", name = "name1", password = "1", email =  "login1@mail.com", data = "data1"}, 
						{info = "Account successfully created", status = 201})

	assert_http_request('post', '/storage/create', 
						{login = "login2", name = "name2", password = "2", email =  "login2@mail.com", data = "data2"},
						{info = "Account successfully created", status = 201})

	assert_http_request('get', '/storage/login1/name', 
						nil,
						{info = "name1", status = 200})

	assert_http_request('get', '/storage/login2/name', 
						nil,
						{info = "name2", status = 200})

	assert_http_request('get', '/storage/login1/email', 
						nil,
						{info = "login1@mail.com", status = 200})

	assert_http_request('get', '/storage/login2/email', 
						nil,
						{info = "login2@mail.com", status = 200})

	assert_http_request('get', '/storage/login1/data', 
						nil,
						{info = "data1", status = 200})

	assert_http_request('get', '/storage/login2/data', 
						nil,
						{info = "data2", status = 200})

	assert_http_request('get', '/storage/login1/password', 
						nil,
						{info = "Invalid field", status = 400})

	assert_http_request('get', '/storage/login2/password', 
						nil,
						{info = "Invalid field", status = 400})

	assert_http_request('get', '/storage/login3/name', 
						nil,
						{info = "Account not found", status = 404})

end

g.test_account_update = function()

	assert_http_request('post', '/storage/create', 
						{login = "login1", name = "name1", password = "1", email =  "login1@mail.com", data = "data1"}, 
						{info = "Account successfully created", status = 201})


	assert_http_request('post', '/storage/create', 
						{login = "login2", name = "name2", password = "2", email =  "login2@mail.com", data = "data2"},
						{info = "Account successfully created", status = 201})


	assert_http_request('get', '/storage/login1/name', 
						nil,
						{info = "name1", status = 200})


	assert_http_request('get', '/storage/login2/name', 
						nil,
						{info = "name2", status = 200})

	assert_http_request('put', '/storage/login1/update/name', 
						{value = "new_name"},
						{info = "Field updated", status = 200})

	assert_http_request('get', '/storage/login1/name', 
						nil,
						{info = "new_name", status = 200})


	assert_http_request('get', '/storage/login2/name', 
						nil,
						{info = "name2", status = 200})

	assert_http_request('put', '/storage/login2/update/data', 
						{value = "new_data"},
						{info = "Field updated", status = 200})


	assert_http_request('get', '/storage/login1/data', 
						nil,
						{info = "data1", status = 200})


	assert_http_request('get', '/storage/login2/data', 
						nil,
						{info = "new_data", status = 200})

	assert_http_request('put', '/storage/login1/update/email', 
						{value = "new_email"},
						{info = "Field updated", status = 200})

	assert_http_request('get', '/storage/login1/email', 
						nil,
						{info = "new_email", status = 200})


	assert_http_request('get', '/storage/login2/email', 
						nil,
						{info = "login2@mail.com", status = 200})

	assert_http_request('put', '/storage/login1/update/password', 
						{value = "4321"},
						{info = "Invalid field", status = 400})

	assert_http_request('put', '/storage/login3/update/name', 
						{value = "4321"},
						{info = "Account not found", status = 404})

end

g.after_each(function()

	local server = g.cluster.main_server
	server:http_request('put','/storage/login1/sign_in', {
		json = {password = "1"}, raise = false})

	server:http_request('put','/storage/login2/sign_in', {
		json = {password = "2"}, raise = false})

	server:http_request('delete','/storage/login1', {
		raise = false})

	server:http_request('delete','/storage/login2', {
		raise = false})

end)

g.after_all(function() 
	g.cluster:stop() 
	fio.rmtree(g.cluster.datadir)
end)