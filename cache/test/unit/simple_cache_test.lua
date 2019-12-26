local t = require('luatest')
local g = t.group('simple_cache_unit_test')

local simple_cache_utils = require('app.roles.simple_cache').utils

require('test.helper.unit')

g.test_account_add = function()
	
	local account = {
	login = "Sai",
	password = "12345",
	bucket_id = 3,
	name = "Saitama",
	email = "saitama@mail.com",
	last_action = os.time(),
	data = "secret3"
	}

	t.assert_equals(simple_cache_utils.account_add(account), true)
	t.assert_equals(simple_cache_utils.account_add(account), false)
	
end

g.test_account_get = function() 
	
	t.assert_equals(simple_cache_utils.account_get("Maki", "email"), 		nil)
	t.assert_equals(simple_cache_utils.account_get("Moto", "name"), 		"Bill")
	t.assert_equals(simple_cache_utils.account_get("Moto", "email"), 		"bill@mail.com")
	t.assert_equals(simple_cache_utils.account_get("Moto", "data"), 		"secret")
	t.assert_equals(simple_cache_utils.account_get("Mura", "name"), 		"Tom")
	t.assert_equals(simple_cache_utils.account_get("Mura", "email"), 		"tom@mail.com")
	t.assert_equals(simple_cache_utils.account_get("Mura", "data"), 		"another secret")

end

g.test_account_update = function()

	t.assert_equals(simple_cache_utils.account_update("Maki", "email", 		42), 	nil)
	t.assert_equals(simple_cache_utils.account_update("Moto", "password", 	"42"), 	true)
	t.assert_equals(simple_cache_utils.account_update("Moto", "name", 	"Paul"), 	true)
	t.assert_equals(simple_cache_utils.account_update("Moto", "email", 	"mail"), 	true)
	t.assert_equals(simple_cache_utils.account_update("Moto", "data", 	"42"), 		true)
	t.assert_equals(simple_cache_utils.account_get("Moto", "name"), 		"Paul")
	t.assert_equals(simple_cache_utils.account_get("Moto", "email"), 		"mail")
	t.assert_equals(simple_cache_utils.account_get("Mura", "name"), 		"Tom")
	t.assert_equals(simple_cache_utils.account_get("Mura", "email"), 		"tom@mail.com")
	t.assert_equals(simple_cache_utils.account_get("Mura", "data"), 		"another secret")

end

g.test_account_delete = function()

	t.assert_equals(simple_cache_utils.account_delete("Sai"), nil)
	t.assert_equals(simple_cache_utils.account_delete("Moto"), true)
	t.assert_equals(simple_cache_utils.account_delete("Moto"), nil)
end

g.before_all(function()
	
	t.assert_equals(require('app.roles.simple_cache').init({is_master = true}), true)

end)

g.before_each(function() 
	box.space.account:truncate()

	box.space.account:insert({
        "Moto",
        "1234",
        1,
        "Bill",
        "bill@mail.com",
        os.time(),
        "secret"
    })

    box.space.account:insert({
        "Mura",
        "1243",
        2,
        "Tom",
        "tom@mail.com",
        os.time(),
        "another secret"
    })

end)