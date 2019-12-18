local t = require('luatest')
local g = t.group('cache_mysql_unit_test')

package.loaded['mysql'] = require('./test/mysql_mock')

local cache_mysql_utils = require('app.roles.cache_mysql').utils

require('test.helper.unit')

g.test_fetch_from = function()
	
	t.assert_equals(cache_mysql_utils.fetch("Liam"), nil)
	
	account = cache_mysql_utils.fetch("Mura")
	t.assert_almost_equals(account[7], os.time(), 5)
	t.assert_equals(account[1], 	"Mura")
	t.assert_equals(account[2], 	"1243")
	t.assert_equals(account[3], 	-1)
	t.assert_equals(account[5], 	"Tom")
	t.assert_equals(account[6], 	"tom@mail.com")
	t.assert_equals(account[8],     "another secret")

end

g.test_verify_session = function()
	
	local account = nil
	local valid, err = cache_mysql_utils.verify_session(account)
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
	valid, err = cache_mysql_utils.verify_session(account)
	t.assert_equals(valid, false)
	t.assert_equals(err, false)

	account[3] = 1
	valid, err = cache_mysql_utils.verify_session(account)
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

	t.assert_equals(cache_mysql_utils.account_add(account), true)
	t.assert_equals(cache_mysql_utils.account_add(account), false)
	
end

g.test_account_sign_in = function() 
	
	t.assert_equals(cache_mysql_utils.account_sign_in("Moto", "1243"), false)
	t.assert_equals(cache_mysql_utils.account_sign_in("Moto", "1234"), true)
	t.assert_equals(cache_mysql_utils.account_sign_in("Mura", "1234"), false)
	t.assert_equals(cache_mysql_utils.account_sign_in("Mura", "1243"), true)
	t.assert_equals(cache_mysql_utils.account_sign_in("Misa", "1234"), nil)

end

g.test_account_sign_out = function() 

	t.assert_equals(cache_mysql_utils.account_sign_out("Moto"), false)
	cache_mysql_utils.account_sign_in("Moto", "1234")
	t.assert_equals(cache_mysql_utils.account_sign_out("Moto"), true)
	t.assert_equals(cache_mysql_utils.account_sign_out("Moto"), false)
	t.assert_equals(cache_mysql_utils.account_sign_out("Mura"), false)
	t.assert_equals(cache_mysql_utils.account_sign_out("Misa"), nil)

end

g.test_account_get = function() 
	
	t.assert_equals(cache_mysql_utils.account_get("Moto", "password"), 	-1)
	t.assert_equals(cache_mysql_utils.account_get("Moto", "email"), 		false)
	t.assert_equals(cache_mysql_utils.account_get("Maki", "email"), 		nil)
	cache_mysql_utils.account_sign_in("Moto", "1234")
	t.assert_equals(cache_mysql_utils.account_get("Moto", "password"), 	-1)
	t.assert_equals(cache_mysql_utils.account_get("Moto", "name"), 		"Bill")
	t.assert_equals(cache_mysql_utils.account_get("Moto", "email"), 		"bill@mail.com")
	t.assert_equals(cache_mysql_utils.account_get("Moto", "data"), 		"secret")
	cache_mysql_utils.account_sign_out("Moto")
	t.assert_equals(cache_mysql_utils.account_get("Mura", "email"), 		false)
	cache_mysql_utils.account_sign_in("Mura", "1243")
	t.assert_equals(cache_mysql_utils.account_get("Mura", "name"), 		"Tom")
	t.assert_equals(cache_mysql_utils.account_get("Mura", "email"), 		"tom@mail.com")
	t.assert_equals(cache_mysql_utils.account_get("Mura", "data"), 		"another secret")
	cache_mysql_utils.account_sign_out("Mura")
	t.assert_equals(cache_mysql_utils.account_get("Mura", "email"), 		false)

end

g.test_account_update = function()

	t.assert_equals(cache_mysql_utils.account_update("Moto", "password", 	42), 	-1)
	t.assert_equals(cache_mysql_utils.account_update("Moto", "email", 		42), 	false)
	t.assert_equals(cache_mysql_utils.account_update("Maki", "email", 		42), 	nil)
	cache_mysql_utils.account_sign_in("Moto", "1234")
	t.assert_equals(cache_mysql_utils.account_update("Moto", "name", 	"Paul"), 	true)
	t.assert_equals(cache_mysql_utils.account_update("Moto", "email", 	"mail"), 	true)
	t.assert_equals(cache_mysql_utils.account_update("Moto", "data", 	"42"), 		true)
	t.assert_equals(cache_mysql_utils.account_get("Moto", "name"), 		"Paul")
	t.assert_equals(cache_mysql_utils.account_get("Moto", "email"), 		"mail")
	t.assert_equals(cache_mysql_utils.account_get("Moto", "data"), 		"42")
	cache_mysql_utils.account_sign_out("Moto")
	t.assert_equals(cache_mysql_utils.account_update("Moto", "email", 		42), 	false)
	t.assert_equals(cache_mysql_utils.account_update("Mura", "email", 		42), 	false)
	t.assert_equals(cache_mysql_utils.account_sign_in("Mura", "1243"), true)
	t.assert_equals(cache_mysql_utils.account_update("Mura", "name", 	"Jim"), 	true)
	cache_mysql_utils.write_behind()
	box.space.account:delete("Mura")
	t.assert_equals(cache_mysql_utils.account_get("Mura", "name"), 		"Jim")
	t.assert_equals(cache_mysql_utils.account_get("Mura", "email"), 	"tom@mail.com")
	t.assert_equals(cache_mysql_utils.account_get("Mura", "data"), 		"another secret")

end

g.test_write_behind = function()

	cache_mysql_utils.account_sign_in("Moto", "1234")
	t.assert_equals(cache_mysql_utils.account_update("Moto", "name", 	"Paul"), 	true)
	t.assert_equals(cache_mysql_utils.account_update("Moto", "email", 	"mail"), 	true)
	t.assert_equals(cache_mysql_utils.account_update("Moto", "data", 	"42"), 		true)
	t.assert_equals(cache_mysql_utils.write_behind(), true)
	box.space.account:delete("Moto")
	account = cache_mysql_utils.fetch("Moto")
	t.assert_equals(account[5], "Paul")
	t.assert_equals(account[6], "mail")
	t.assert_equals(account[8], "42")
end

g.test_account_delete = function()

	cache_mysql_utils.account_sign_out("Mura")
	t.assert_equals(cache_mysql_utils.account_delete("Moto"), false)
	t.assert_equals(cache_mysql_utils.account_delete("Sai"), nil)
	cache_mysql_utils.account_sign_in("Moto", "1234")
	t.assert_equals(cache_mysql_utils.account_delete("Moto"), true)
	t.assert_equals(cache_mysql_utils.account_delete("Moto"), nil)
	t.assert_equals(cache_mysql_utils.account_delete("Mura"), false)
	cache_mysql_utils.account_sign_in("Mura", "1243")	
	t.assert_equals(cache_mysql_utils.account_delete("Mura"), true)
	t.assert_equals(cache_mysql_utils.account_delete("Mura"), nil)
end

g.before_all(function()
	
	t.assert_equals(require('app.roles.cache_mysql').init({is_master = true}), true)

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

	package.loaded['mysql'].connect():rollback()
	
end)