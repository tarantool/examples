local t = require('luatest')
local g = t.group('simple_cache_unit_test')

local simple_cache_utils = require('app.roles.simple_cache').utils

require('test.helper.unit')

g.test_verify_session = function()
	
	local account = nil
	local valid, err = simple_cache_utils.verify_session(account)
	t.assert_equals(valid, false)
	t.assert_equals(err, nil)

	account = {
		"Moto",
		"1234",
		-1,
		1,
		"Bill",
		"bill@mail.com",
		os.time(),
		"secret"
	}
	valid, err = simple_cache_utils.verify_session(account)
	t.assert_equals(valid, false)
	t.assert_equals(err, false)

	account[3] = 1
	valid, err = simple_cache_utils.verify_session(account)
	t.assert_equals(valid, true)
	t.assert_equals(err, nil)

end

g.test_account_add = function()
	
	local account = {
	login = "Sai",
	password = "12345",
	session = -1,
	bucket_id = 3,
	name = "Saitama",
	email = "saitama@mail.com",
	last_action = os.time(),
	data = "secret3"
	}

	t.assert_equals(simple_cache_utils.account_add(account), true)
	t.assert_equals(simple_cache_utils.account_add(account), false)
	
end

g.test_account_sign_in = function() 
	
	t.assert_equals(simple_cache_utils.account_sign_in("Moto", "1243"), false)
	t.assert_equals(simple_cache_utils.account_sign_in("Moto", "1234"), true)
	t.assert_equals(simple_cache_utils.account_sign_in("Mura", "1234"), false)
	t.assert_equals(simple_cache_utils.account_sign_in("Mura", "1243"), true)
	t.assert_equals(simple_cache_utils.account_sign_in("Misa", "1243"), nil)

end

g.test_account_sign_out = function() 

	t.assert_equals(simple_cache_utils.account_sign_out("Moto"), false)
	simple_cache_utils.account_sign_in("Moto", "1234")
	t.assert_equals(simple_cache_utils.account_sign_out("Moto"), true)
	t.assert_equals(simple_cache_utils.account_sign_out("Moto"), false)
	t.assert_equals(simple_cache_utils.account_sign_out("Mura"), false)
	t.assert_equals(simple_cache_utils.account_sign_out("Misa"), nil)

end

g.test_account_get = function() 
	
	t.assert_equals(simple_cache_utils.account_get("Moto", "password"), 	-1)
	t.assert_equals(simple_cache_utils.account_get("Moto", "email"), 		false)
	t.assert_equals(simple_cache_utils.account_get("Maki", "email"), 		nil)
	simple_cache_utils.account_sign_in("Moto", "1234")
	t.assert_equals(simple_cache_utils.account_get("Moto", "name"), 		"Bill")
	t.assert_equals(simple_cache_utils.account_get("Moto", "email"), 		"bill@mail.com")
	t.assert_equals(simple_cache_utils.account_get("Moto", "data"), 		"secret")
	simple_cache_utils.account_sign_out("Moto")
	t.assert_equals(simple_cache_utils.account_get("Mura", "email"), 		false)
	simple_cache_utils.account_sign_in("Mura", "1243")
	t.assert_equals(simple_cache_utils.account_get("Mura", "name"), 		"Tom")
	t.assert_equals(simple_cache_utils.account_get("Mura", "email"), 		"tom@mail.com")
	t.assert_equals(simple_cache_utils.account_get("Mura", "data"), 		"another secret")
	simple_cache_utils.account_sign_out("Mura")
	t.assert_equals(simple_cache_utils.account_get("Mura", "email"), 		false)

end

g.test_account_update = function()

	t.assert_equals(simple_cache_utils.account_update("Moto", "password", 	42), 	-1)
	t.assert_equals(simple_cache_utils.account_update("Moto", "email", 		42), 	false)
	t.assert_equals(simple_cache_utils.account_update("Maki", "email", 		42), 	nil)
	simple_cache_utils.account_sign_in("Moto", "1234")
	t.assert_equals(simple_cache_utils.account_update("Moto", "password", 	42), 	-1)
	t.assert_equals(simple_cache_utils.account_update("Moto", "name", 	"Paul"), 	true)
	t.assert_equals(simple_cache_utils.account_update("Moto", "email", 	"mail"), 	true)
	t.assert_equals(simple_cache_utils.account_update("Moto", "data", 	"42"), 		true)
	t.assert_equals(simple_cache_utils.account_get("Moto", "name"), 		"Paul")
	t.assert_equals(simple_cache_utils.account_get("Moto", "email"), 		"mail")
	t.assert_equals(simple_cache_utils.account_get("Moto", "data"), 		"42")
	simple_cache_utils.account_sign_out("Moto")
	t.assert_equals(simple_cache_utils.account_update("Moto", "email", 		42), 	false)
	simple_cache_utils.account_sign_in("Mura", "1243")
	t.assert_equals(simple_cache_utils.account_get("Mura", "name"), 		"Tom")
	t.assert_equals(simple_cache_utils.account_get("Mura", "email"), 		"tom@mail.com")
	t.assert_equals(simple_cache_utils.account_get("Mura", "data"), 		"another secret")

end

g.test_account_delete = function()

	t.assert_equals(simple_cache_utils.account_delete("Moto"), false)
	t.assert_equals(simple_cache_utils.account_delete("Sai"), nil)
	simple_cache_utils.account_sign_in("Moto", "1234")
	t.assert_equals(simple_cache_utils.account_delete("Moto"), true)
	t.assert_equals(simple_cache_utils.account_delete("Moto"), nil)
	t.assert_equals(simple_cache_utils.account_delete("Mura"), false)	
end

g.before_all(function()
	
	t.assert_equals(require('app.roles.simple_cache').init({is_master = true}), true)

end)

g.before_each(function() 
	box.space.account:truncate()

	box.space.account:insert({
        "Moto",
        "1234",
        -1,
        1,
        "Bill",
        "bill@mail.com",
        os.time(),
        "secret"
    })

    box.space.account:insert({
        "Mura",
        "1243",
        -1,
        2,
        "Tom",
        "tom@mail.com",
        os.time(),
        "another secret"
    })

end)