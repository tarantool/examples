-- module for checking arguments in functions
local checks = require('checks')

-- module for working with numbers
local decnumber = require('ldecnumber')

local lru = require('lru')
local mysql = require('mysql')
local log = require('log')

local field_no = {
    name = 5,
    email = 6,
    data = 8,
    bucket_id = 4
}
local lru_cache = nil

-- ========================================================================= --
-- mysql section
-- ========================================================================= --
local using_mysql = false
local conn = nil
if using_mysql then
    conn = mysql.connect({
        host = '127.0.0.1', 
        user = 'root', 
        password = '1234', 
        db = 'tarantool'
    })
end

local function fetch_from_mysql(login)
    checks('string')

    local account = conn:execute(string.format("SELECT * FROM account WHERE login = \'%s\'", 
        login
        ))

    if (#account[1] == 0) then 
        return nil
    end

    account = account[1][1]
    local time = os.time()
    local tmp = {
        account.login,
        account.password,
        account.session,
        account.bucket_id,
        account.name,
        account.email,
        time,
        account.data
    }

    box.space.account:insert(tmp)

    tmp = {
        login = account.login,
        password = account.password,
        session = account.session,
        bucket_id = account.bucket_id,
        name = account.name,
        email = account.email,
        last_action = time,
        data = account.data
    }

    log.info(string.format("\'%s\' uploaded from mysql",
        tmp.login
        ))

    return tmp
end

-- ========================================================================= --
-- vinyl section
-- ========================================================================= --
local using_vinyl = true

local function fetch_from_vinyl(login)
    checks('string')

    local account = box.space.account_vinyl:get(login)
    if account == nil then 
        return nil
    end

    local time = os.time()
    local tmp = {
        account.login,
        account.password,
        account.session,
        account.bucket_id,
        account.name,
        account.email,
        time,
        account.data
    }

    box.space.account:insert(tmp)    

    tmp = {
        login = account.login,
        password = account.password,
        session = account.session,
        bucket_id = account.bucket_id,
        name = account.name,
        email = account.email,
        last_action = time,
        data = account.data
    }

    log.info(string.format("\'%s\' uploaded from vinyl",
        tmp.login
        ))

    return tmp
end

local function peek_vinyl(login)
    checks('string')

    local account = box.space.account_vinyl:get(login)
    if account == nil then 
        return false
    end

    return true
end


-- ========================================================================= --
-- write behind section
-- ========================================================================= --

local write_queue = {}

local function write_behind()

    for login, _ in pairs(write_queue) do

        local account = box.space.account:get(login)
        if (account ~= nil) then
            
            if using_mysql then
                conn:execute(string.format("REPLACE INTO account value (\'%s\', \'%s\', \'%d\', \'%d\', \'%s\', \'%s\', \'%s\')", 
                    account.login, 
                    account.password, 
                    account.session, 
                    account.bucket_id, 
                    account.name, 
                    account.email, 
                    account.data
                ))

                log.info(string.format("\'%s\' updated in mysql", 
                    account.login
                ))
            end
            
            if using_vinyl then 
                box.space.account_vinyl:upsert({
                    account.login, 
                    account.password, 
                    account.session, 
                    account.bucket_id, 
                    account.name, 
                    account.email, 
                    account.data
                }, {
                    {'=', 1, account.login},
                    {'=', 2, account.password},
                    {'=', 3, account.session},
                    {'=', 4, account.bucket_id},
                    {'=', 5, account.name},
                    {'=', 6, account.email},
                    {'=', 7, account.data}
                })

                log.info(string.format("\'%s\' updated in vinyl", 
                    account.login
                ))
            end
        end
    end

    write_queue = {}
    return true
end

local function set_to_update(login)
    checks('string')

    if write_queue[login] == nil then
        write_queue[login] = true
    end

    return true
end

-- ========================================================================= --
-- update section
-- ========================================================================= --

local update_period = 5
local last_update = os.time()
local cache_size = 2

local function update_storage()
    if(os.time() - last_update) < update_period then
        return false
    end

    write_behind()
    last_update = os.time()
    return true
end

local function update_cache(login)
    checks('string')

    local result, err = lru_cache:touch(login)

    if err ~= nil then
        return nil, err
    end

    if result == true then 
        return true
    end
    log.info(string.format("Removing \'%s\' from cache", result))
    box.space.account:delete(result)

    return true
end

-- ========================================================================= --
-- supporting functions
-- ========================================================================= --
local function fetch(login)
    checks('string')

    if using_mysql then
        return fetch_from_mysql(login)
    end

    if using_vinyl then 
        return fetch_from_vinyl(login)
    end

    return nil
end

local function verify_session(account)
    if account == nil then
        return false, nil
    end

    if account.session == -1 then
        return false, false
    end

    return true
end

-- ========================================================================= --
-- server functions
-- ========================================================================= --

local function init_spaces()
    local account = box.schema.space.create(
        'account',
        -- extra parameters
        {
            -- format for stored tuples
            format = {
                {'login', 'string'},
                {'password', 'string'},
                {'session', 'number'},
                {'bucket_id', 'unsigned'},
                {'name', 'string'},
                {'email', 'string'},
                {'last_action', 'unsigned'},
                {'data', 'string'}
            },
            -- creating the space only if it doesn't exist
            if_not_exists = true,
            engine = 'memtx'
        }
    )

    account:create_index('login', {
        parts = {'login'},
        if_not_exists = true,
    })

    account:create_index('bucket_id', {
        parts = {'bucket_id'},
        unique = false,
        if_not_exists = true,
    })

    if using_vinyl then
        local account_vinyl = box.schema.space.create(
            'account_vinyl',
            -- extra parameters
            {
                -- format for stored tuples
                format = {
                    {'login', 'string'},
                    {'password', 'string'},
                    {'session', 'number'},
                    {'bucket_id', 'unsigned'},
                    {'name', 'string'},
                    {'email', 'string'},
                    {'data', 'string'}
                },
                -- creating the space only if it doesn't exist
                if_not_exists = true,
                engine = 'vinyl'
            }
        )

        account_vinyl:create_index('login', {
            parts = {'login'},
            if_not_exists = true,
        })

        account_vinyl:create_index('bucket_id', {
            parts = {'bucket_id'},
            unique = false,
            if_not_exists = true,
        })
    end

    lru_cache = lru.new(cache_size)
end

local function account_add(account)
    update_storage()
    local tmp = box.space.account:get(account.login)
    if tmp == nil then
        tmp = fetch(account.login)
    end

    if tmp ~= nil then
        return false
    end

    box.space.account:insert({
        account.login,
        account.password,
        -1,
        account.bucket_id,
        account.name,
        account.email,
        os.time(),
        account.data
    })

    update_cache(account.login)

    if using_mysql or using_vinyl then
        set_to_update(account.login)
    end

    return true
end

local function account_sign_in(login, password)
    checks('string', 'string')
    update_storage()

    local account = box.space.account:get(login)
    if account == nil then
        account = fetch(login)
    end

    if account == nil then   -- checking if the account was found
        return nil
    end

    if password ~= account.password then
        return false
    end

    box.space.account:update({ login } , {
        {'=', 3, 1},
        {'=', 7, os.time()}
    })
    update_cache(login)
    set_to_update(login)

    return true
end

local function account_sign_out(login)
    checks('string')
    update_storage()

    local account = box.space.account:get(login)
    if account == nil then
        account = fetch(login)
    end

    local valid, err = verify_session(account)
    if not valid then
        return err
    end

    box.space.account:update({ login } , {
        {'=', 3, -1},
        {'=', 7, os.time()}
    })
    update_cache(login)
    set_to_update(login)

    return true
end

local function account_update(login, field, value)
    update_storage()

    local field_n = field_no[field]
    if field_n == nil then 
        return -1
    end

    -- finding the required account in the database
    local account = box.space.account:get(login)
    if account == nil then
        account = fetch(login)
    end

    local valid, err = verify_session(account)
    if not valid then
        return err
    end

    -- updating the balance
    box.space.account:update({ login }, {
        { '=', field_n, value},
        { '=', 7, os.time()}
    })
    update_cache(login)
    set_to_update(login)

    return true
end

local function account_get(login, field)
    checks('string', 'string')
    update_storage()

    local field_n = field_no[field]
    if field_n == nil then 
        return -1
    end

    local account = box.space.account:get(login)
    if account == nil then
        account = fetch(login)
    end

    local valid, err = verify_session(account)
    if not valid then
        return err
    end

    box.space.account:update({login}, {
        {'=', 7, os.time()}
    })
    update_cache(login)

    return account[field_n]
end

local function account_delete(login)
    checks('string')
    update_storage()

    local account = box.space.account:get(login)
    if account == nil then
        account = fetch(login)
    end

    local valid, err = verify_session(account)
    if not valid then
        return err
    end

    if using_mysql then
        conn:begin()
        conn:execute(string.format(
            "DELETE FROM account WHERE login = \'%s\'", login 
            ))

        box.space.account:delete(login)
        conn:commit()
    end

    if using_vinyl then
        if peek_vinyl(login) then
            box.space.account_vinyl:delete(login)
        end
    end

    lru_cache:delete(login)
    local account = box.space.account:delete(login)
    return true
end

local function init(opts)
    if opts.is_master then

        -- calling the space initialization function
        init_spaces()

        box.schema.func.create('account_add', {if_not_exists = true})
        box.schema.func.create('account_sign_in', {if_not_exists = true})
        box.schema.func.create('account_sign_out', {if_not_exists = true})
        box.schema.func.create('account_delete', {if_not_exists = true})
        box.schema.func.create('account_update', {if_not_exists = true})
        box.schema.func.create('account_get', {if_not_exists = true})

        box.schema.role.grant('public', 'execute', 'function', 'account_add', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'account_sign_in', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'account_sign_out', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'account_delete', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'account_update', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'account_get', {if_not_exists = true})

    end

    rawset(_G, 'account_add', account_add)
    rawset(_G, 'account_sign_in', account_sign_in)
    rawset(_G, 'account_sign_out', account_sign_out)
    rawset(_G, 'account_get', account_get)
    rawset(_G, 'account_delete', account_delete)
    rawset(_G, 'account_update', account_update)

    return true
end

return {
    role_name = 'cache',
    init = init,
    dependencies = {
        'cartridge.roles.vshard-storage',
    },
}
