local checks = require('checks')
local lru = require('lru')
local log = require('log')

local lru_cache = nil

-- ========================================================================= --
-- update section
-- ========================================================================= --
local cache_size = 2

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

local function verify_field(field)
    checks('string')
    
    if (field == 'name') or (field == 'email') or (field == 'data') 
    or (field == 'password') or (field == 'login') or (field == 'last_action') then
        return true
    end

    return false
end

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

    lru_cache = lru.new(cache_size) --least recently used cache
    for k, account in box.space.account:pairs() do --recover lru cache 
        update_cache(account[1])
    end
end

local function account_add(account)
    
    local tmp = box.space.account:get(account.login) --check if account already exists
    if tmp ~= nil then
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

    return true
end

local function account_update(login, field, value)

    if(verify_field(field) ~= true) then 
        return -1
    end

    local account = box.space.account:get(login) --check if account already exists
    if account == nil then
        return nil
    end

    account = tuple_to_map(account)
    account[field] = value
    account["last_action"] = os.time()

    box.space.account:replace(box.space.account:frommap(account))

    update_cache(account.login)

    return true
end

local function account_get(login, field)
    checks('string', 'string')

    if(verify_field(field) ~= true) then 
        return -1
    end

    local account = box.space.account:get(login)
    if account == nil then
        return nil
    end

    account = tuple_to_map(account)
    account["last_action"] = os.time()

    box.space.account:replace(box.space.account:frommap(account))

    update_cache(account.login)

    return account[field]
end

local function account_delete(login)
    checks('string')

    local account = box.space.account:get(login)
    if account == nil then
        return nil
    end

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

    end

    rawset(_G, 'account_add', account_add)
    rawset(_G, 'account_get', account_get)
    rawset(_G, 'account_delete', account_delete)
    rawset(_G, 'account_update', account_update)

    return true
end

return {
    role_name = 'simple_cache',
    init = init,
    dependencies = {
        'cartridge.roles.vshard-storage',
    },
    utils = {
        account_add = account_add, 
        account_update = account_update,
        account_delete = account_delete, 
        account_get = account_get,
    }
}
