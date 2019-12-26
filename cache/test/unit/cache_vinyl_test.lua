local t = require('luatest')
local g = t.group('cache_vinyl_unit_test')

local cache_vinyl_utils = require('app.roles.cache_vinyl').utils

require('test.helper.unit')

g.test_fetch = function()
	
	t.assert_equals(cache_vinyl_utils.fetch("Liam"), nil)
	
	account = cache_vinyl_utils.fetch("Mura")
	t.assert_almost_equals(account[6], os.time(), 5)
	t.assert_equals(account[1], 	"Mura")
	t.assert_equals(account[2], 	"1243")
	t.assert_equals(account[4], 	"Tom")
	t.assert_equals(account[5], 	"tom@mail.com")
	t.assert_equals(account[7],     "another secret")

end

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

	t.assert_equals(cache_vinyl_utils.account_add(account), true)
	t.assert_equals(cache_vinyl_utils.account_add(account), false)
	
end

g.test_peek_vinyl = function()
	
	local account = {
	login = "Sai",
	password = "12345",
	bucket_id = 3,
	name = "Saitama",
	email = "saitama@mail.com",
	last_action = os.time(),
	data = "secret3"
	}

	t.assert_equals(cache_vinyl_utils.account_add(account), true)
	t.assert_equals(cache_vinyl_utils.peek_vinyl("Sai"), false)
	t.assert_equals(cache_vinyl_utils.peek_vinyl("Mura"), true)

end

g.test_account_get = function() 
	
	t.assert_equals(cache_vinyl_utils.account_get("Maki", "email"), 	nil)
	t.assert_equals(cache_vinyl_utils.account_get("Moto", "name"), 		"Bill")
	t.assert_equals(cache_vinyl_utils.account_get("Moto", "email"), 	"bill@mail.com")
	t.assert_equals(cache_vinyl_utils.account_get("Moto", "data"), 		"secret")
	t.assert_equals(cache_vinyl_utils.account_get("Mura", "name"), 		"Tom")
	t.assert_equals(cache_vinyl_utils.account_get("Mura", "email"), 	"tom@mail.com")
	t.assert_equals(cache_vinyl_utils.account_get("Mura", "data"), 		"another secret")

end

g.test_account_update = function()

	t.assert_equals(cache_vinyl_utils.account_update("Maki", "email", 		42), 	nil)
	t.assert_equals(cache_vinyl_utils.account_update("Moto", "name", 	"Paul"), 	true)
	t.assert_equals(cache_vinyl_utils.account_update("Moto", "email", 	"mail"), 	true)
	t.assert_equals(cache_vinyl_utils.account_update("Moto", "data", 	"42"), 		true)
	t.assert_equals(cache_vinyl_utils.account_get("Moto", "name"), 		"Paul")
	t.assert_equals(cache_vinyl_utils.account_get("Moto", "email"), 		"mail")
	t.assert_equals(cache_vinyl_utils.account_get("Moto", "data"), 		"42")
	t.assert_equals(cache_vinyl_utils.account_update("Mura", "name", 	"Jim"), 	true)
	cache_vinyl_utils.write_behind()
	box.space.account:delete("Mura")
	t.assert_equals(cache_vinyl_utils.account_get("Mura", "name"), 		"Jim")
	t.assert_equals(cache_vinyl_utils.account_get("Mura", "email"), 	"tom@mail.com")
	t.assert_equals(cache_vinyl_utils.account_get("Mura", "data"), 		"another secret")

end

g.test_write_behind = function()

	t.assert_equals(cache_vinyl_utils.account_update("Moto", "name", 	"Paul"), 	true)
	t.assert_equals(cache_vinyl_utils.account_update("Moto", "email", 	"mail"), 	true)
	t.assert_equals(cache_vinyl_utils.account_update("Moto", "data", 	"42"), 		true)
	t.assert_equals(cache_vinyl_utils.write_behind(), true)
	box.space.account:delete("Moto")
	account = cache_vinyl_utils.fetch("Moto")
	t.assert_equals(account[4], "Paul")
	t.assert_equals(account[5], "mail")
	t.assert_equals(account[7], "42")
end

g.test_account_delete = function()

	t.assert_equals(cache_vinyl_utils.account_delete("Sai"), nil)
	t.assert_equals(cache_vinyl_utils.account_delete("Moto"), true)
	t.assert_equals(cache_vinyl_utils.account_delete("Moto"), nil)
	t.assert_equals(cache_vinyl_utils.account_delete("Mura"), true)
	t.assert_equals(cache_vinyl_utils.account_delete("Mura"), nil)
end

g.before_all(function()
	
	t.assert_equals(require('app.roles.cache_vinyl').init({is_master = true}), true)

end)

g.before_each(function() 
	box.space.account:truncate()
	box.space.account_vinyl:truncate()

	box.space.account:insert({
        "Moto",
        "1234",
        1,
        "Bill",
        "bill@mail.com",
        os.time(),
        "secret"
    })

    box.space.account_vinyl:insert({
        "Moto",
        "1234",
        1,
        "Bill",
        "bill@mail.com",
        os.time(),
        "secret"
    })

    box.space.account_vinyl:insert({
        "Mura",
        "1243",
        2,
        "Tom",
        "tom@mail.com",
        os.time(),
        "another secret"
    })

end)