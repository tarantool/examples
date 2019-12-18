local checks = require('checks')
local lru = require('lru')
local log = require('log')

local field_no = {
    name = 5,
    email = 6,
    data = 8,
}

local function verify_session(account) --verify if account exists and session is up
    if account == nil then --if account is not found
        return false, nil
    end

    if account[3] == 1 then --if session is up return true
        return true
    end

    return false, false
end

local function init_spaces()
    local account = box.schema.space.create(
        'account',
        {
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
end

local function account_add(account)
    local tmp = box.space.account:get(account.login) --check if account already exists
    if tmp ~= nil then
        return false
    end

    box.space.account:insert({
        account.login,
        account.password,
        1,
        account.bucket_id,
        account.name,
        account.email,
        os.time(),
        account.data
    })

    return true
end

local function account_sign_in(login, password)
    checks('string', 'string')

    local account = box.space.account:get(login) --check if account exists, return nil if not
    if account == nil then 
        return nil
    end

    if password ~= account[2] then --verify password, return false if password is wrong
        return false
    end

    box.space.account:update({ login } , {
        {'=', 3, 1},
        {'=', 7, os.time()} --update last action timestamp
    })

    return true
end

local function account_sign_out(login)
    checks('string')

    local account = box.space.account:get(login) --get and verify account
    local valid, err = verify_session(account)
    if not valid then
        return err
    end

    box.space.account:update({ login } , {
        {'=', 3, -1},
        {'=', 7, os.time()} --update last action timestamp
    })

    return true
end

local function account_update(login, field, value)

    local field_n = field_no[field] --check if requested field is valid
    if field_n == nil then 
        return -1
    end

    local account = box.space.account:get(login) --get and verify account
    local valid, err = verify_session(account)
    if not valid then
        return err
    end

    box.space.account:update({ login }, {
        { '=', field_n, value}, --update field
        { '=', 7, os.time()} --update last action timestamp
    })

    return true
end

local function account_get(login, field)
    checks('string', 'string')

    local field_n = field_no[field] --check if requested field is valid
    if field_n == nil then 
        return -1
    end

    local account = box.space.account:get(login) --get and verify account
    local valid, err = verify_session(account)
    if not valid then
        return err
    end

    box.space.account:update({login}, {
        {'=', 7, os.time()} --update last action timestamp
    })

    return account[field_n]
end

local function account_delete(login)
    checks('string')

    local account = box.space.account:get(login) --get and verify account
    local valid, err = verify_session(account)
    if not valid then
        return err
    end

    local account = box.space.account:delete(login)

    return true
end

local function init(opts)
    if opts.is_master then

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
    role_name = 'simple_cache',
    init = init,
    dependencies = {
        'cartridge.roles.vshard-storage',
    },
    utils = {
        verify_session = verify_session,
        account_add = account_add, 
        account_update = account_update,
        account_delete = account_delete, 
        account_get = account_get,
        account_sign_in = account_sign_in, 
        account_sign_out = account_sign_out,
    }
}
