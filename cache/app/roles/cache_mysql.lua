local checks = require('checks')
local lru = require('lru')
local mysql = require('mysql')
local log = require('log')
local fiber = require('fiber')

local lru_cache

-- ========================================================================= --
-- mysql section
-- ========================================================================= --
local conn

local function fetch(login) --get tuple from mysql storage if it isn't present in cache
    checks('string')

    local account = conn:execute(string.format("SELECT * FROM account WHERE login = \'%s\'", login))

    if (#account[1] == 0) then 
        return nil
    end

    account = account[1][1]
    local tmp = {
        account.login,
        account.password,
        account.bucket_id,
        account.name,
        account.email,
        os.time(),
        account.data
    }

    box.space.account:insert(tmp) --insert tuple into cache

    log.info(string.format("\'%s\' uploaded from mysql", tmp[1]))

    return tmp
end

-- ========================================================================= --
-- write behind section
-- ========================================================================= --

local batch_size = 2
local write_queue = {}

local function update_batch(batch)

    for _, account in ipairs(batch) do
        
        conn:execute(string.format("REPLACE INTO account value (\'%s\', \'%s\', \'%d\', \'%s\', \'%s\', \'%d\', \'%s\')", 
            account[1], 
            account[2], 
            account[3], 
            account[4], 
            account[5], 
            account[6], 
            account[7]
        ))

        log.info(string.format("\'%s\' updated in mysql", account[1]))

    end
end

local function write_behind() --update changed tuple in vinyl storage

    local batch = {}
    for login, _ in pairs(write_queue) do
        local account = box.space.account:get(login)
        if (account ~= nil) then
            table.insert(batch, account)
        end
            
        if (#batch >= batch_size) then
            conn:begin()
            update_batch(batch)

            for _,  acc in pairs(batch) do
                write_queue[acc['login']] = nil
            end

            batch = {}
            conn:commit()
        end
    end

    if (#batch ~= 0) then
        conn:begin()
        update_batch(batch)

        for _,  acc in pairs(batch) do
            write_queue[acc['login']] = nil
        end

        batch = {}
        conn:commit()
    end

    local length = 0
    for acc, status in pairs(write_queue) do
        length = length + 1
    end

    if (length == 0) then
        log.info("All updates are applied")
    else
        log.warn(string.format("%d updates failed", length))
    end

    return true
end

local function set_to_update(login) --set tuple to be updated in mysql
    checks('string')

    if write_queue[login] == nil then
        write_queue[login] = true
    end

    return true
end

-- ========================================================================= --
-- update section
-- ========================================================================= --

local update_period = 10
local last_update = os.time()
local cache_size = 2

local function fiber_routine()
    while true do
        fiber.testcancel()
        if (os.time() - last_update) > update_period then
            write_behind()
            last_update = os.time()
        end
        
        fiber.sleep(1)
    end
end

local function update_cache(login) --remove least recently used tuples from cache
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

local function tuple_to_map(account)
    
    local res = 
    {
        login = account[1],
        password = account[2],
        bucket_id = account[3],
        name = account[4],
        email = account[5],
        last_action = account[6],
        data = account[7],
    }

    return res
end

local function verify_field(field)
    checks('string')
    
    if (field == 'name') or (field == 'email') or (field == 'data') 
    or (field == 'password') or (field == 'login') or (field == 'last_action') then
        return true
    end

    return false
end

-- ========================================================================= --
-- storage functions
-- ========================================================================= --

local function init_spaces()
    local account = box.schema.space.create(
        'account',
        {
            format = {
                {'login', 'string'},
                {'password', 'string'},
                {'bucket_id', 'unsigned'},
                {'name', 'string'},
                {'email', 'string'},
                {'last_action', 'unsigned'},
                {'data', 'string'}
            },
            if_not_exists = true,
            engine = 'memtx',
            temporary = false,
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

    conn = mysql.connect({
        host = '127.0.0.1', 
        user = 'root', 
        password = '1234', 
        db = 'tarantool'
    })

    fiber.create(fiber_routine)

    lru_cache = lru.new(cache_size) --least recently used cache
    for k, account in box.space.account:pairs() do --recover lru cache 
        update_cache(account[1])
    end
end

local function account_add(account)

    local tmp = box.space.account:get(account.login) --check if account already exists
    if tmp == nil then
        tmp = fetch(account.login)
    end

    if tmp ~= nil then
        update_cache(account.login)
        return false
    end

    box.space.account:insert({
        account.login,
        account.password,
        account.bucket_id,
        account.name,
        account.email,
        os.time(),
        account.data
    })

    update_cache(account.login)
    set_to_update(account.login)

    return true
end

local function account_update(login, field, value)

    if(verify_field(field) ~= true) then 
        return -1
    end

    local account = box.space.account:get(login) --check if account exists, return nil if not
    if account == nil then
        account = fetch(login) --check additional storage if it isn't present in cache
    end
    
    if account == nil then
        return nil
    end

    account = tuple_to_map(account)
    account[field] = value
    account["last_action"] = os.time()

    box.space.account:replace(box.space.account:frommap(account))

    update_cache(login) --update account's position in lru cache
    set_to_update(login) --set account to be updated in mysql storage

    return true
end

local function account_get(login, field)
    checks('string', 'string')

    if(verify_field(field) ~= true) then 
        return -1
    end

    local account = box.space.account:get(login) --check if account exists, return nil if not
    if account == nil then
        account = fetch(login) --check additional storage if it isn't present in cache
    end

    if account == nil then
        return nil
    end

    account = tuple_to_map(account)
    account["last_action"] = os.time()

    box.space.account:replace(box.space.account:frommap(account))
    
    update_cache(login) --update account's position in lru cache
    set_to_update(login) --set account to be updated in mysql storage
    return account[field]
end

local function account_delete(login)
    checks('string')
    
    local account = box.space.account:get(login) --check if account exists, return nil if not
    if account == nil then
        account = fetch(login) --check additional storage if it isn't present in cache
    end
   
    if account == nil then
        return nil
    end

    conn:execute(string.format("DELETE FROM account WHERE login = \'%s\'", login ))
    box.space.account:delete(login)


    lru_cache:delete(login)
    local account = box.space.account:delete(login)
    return true
end

local function init(opts)
    if opts.is_master then

        init_spaces()

        box.schema.func.create('account_add', {if_not_exists = true})
        box.schema.func.create('account_delete', {if_not_exists = true})
        box.schema.func.create('account_update', {if_not_exists = true})
        box.schema.func.create('account_get', {if_not_exists = true})
        box.schema.func.create('tuple_to_map', {if_not_exists = true})
        box.schema.func.create('verify_field', {if_not_exists = true})

        box.schema.role.grant('public', 'execute', 'function', 'account_add', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'account_delete', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'account_update', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'account_get', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'tuple_to_map', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'verify_field', {if_not_exists = true})

    end

    rawset(_G, 'account_add', account_add)
    rawset(_G, 'account_get', account_get)
    rawset(_G, 'account_delete', account_delete)
    rawset(_G, 'account_update', account_update)

    return true
end

return {
    role_name = 'cache_mysql',
    init = init,
    dependencies = {
        'cartridge.roles.vshard-storage',
    },
    utils = {
        write_behind = write_behind,
        set_to_update = set_to_update,
        update_cache = update_cache,
        fetch = fetch,
        account_add = account_add, 
        account_update = account_update,
        account_delete = account_delete, 
        account_get = account_get,
        tuple_to_map = tuple_to_map,
        verify_field = verify_field,
    }
}
