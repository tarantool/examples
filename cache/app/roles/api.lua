local cartridge = require('cartridge')
local errors = require('errors')

local err_vshard_router = errors.new_class("Vshard routing error")
local err_httpd = errors.new_class("httpd error")

local function verify_response(response, error, req)
    
    if error then
        local resp = req:render({json = {
            info = "Internal error",
            error = error
        }})
        resp.status = 500
        return resp
    end

    if response == nil then
        local resp = req:render({json = {
            info = "Account not found",
            error = error
        }})
        resp.status = 404
        return resp
    end

    if response == -1 then
        local resp = req:render({json = {
            info = "Invalid field",
        }})
        resp.status = 400
        return resp
    end

    if response == false then
        local resp = req:render({json = {
            info = "Account with such login exists",
        }})
        resp.status = 409
        return resp
    end

    return true
end

local function http_account_add(req)
    local time_stamp = os.clock()
    local account = req:json()
    local router = cartridge.service_get('vshard-router').get()
    local bucket_id = router:bucket_id(account.login)
    account.bucket_id = bucket_id

    local success, error = err_vshard_router:pcall(
        router.call,
        router,
        bucket_id,
        'write',
        'account_add',
        {account}
    )

    local verification_status = verify_response(success, error, req)
    if verification_status ~= true then
        return verification_status
    end

    local resp = req:render({json = { info = "Account successfully created", time = os.clock() - time_stamp}})
    resp.status = 201
    return resp
end

local function http_account_delete(req)
    local time_stamp = os.clock()
    local login = req:stash('login')
	local router = cartridge.service_get('vshard-router').get()
    local bucket_id = router:bucket_id(login)

	local success, error = err_vshard_router:pcall(
        router.call,
        router,
        bucket_id,
        'read',
        'account_delete',
        {login}
    )

    local verification_status = verify_response(success, error, req)
    if verification_status ~= true then
        return verification_status
    end

    local resp = req:render({json = {info = "Account deleted", time = os.clock() - time_stamp}})
    resp.status = 200
    return resp
end

local function http_account_update(req)
    local time_stamp = os.clock()
	local login = req:stash('login')
	local field = req:stash('field')
	local router = cartridge.service_get('vshard-router').get()
    local bucket_id = router:bucket_id(login)

	local value = req:json().value

	local success, error = err_vshard_router:pcall(
        router.call,
        router,
        bucket_id,
        'write',
        'account_update',
        {login, field, value}
    )

    local verification_status = verify_response(success, error, req)
    if verification_status ~= true then
        return verification_status
    end

    local resp = req:render({json = {info = "Field updated", time = os.clock() - time_stamp}})
    resp.status = 200
    return resp
end

local function http_account_get(req)
    local time_stamp = os.clock()
	local login = req:stash('login')
	local field = req:stash('field')
	local router = cartridge.service_get('vshard-router').get()
    local bucket_id = router:bucket_id(login)

	local account_data, error = err_vshard_router:pcall(
        router.call,
        router,
        bucket_id,
        'read',
        'account_get',
        {login, field}
    )

    local verification_status = verify_response(account_data, error, req)
    if verification_status ~= true then
        return verification_status
    end

    local resp = req:render({json = {info = account_data, time = os.clock() - time_stamp}})
    resp.status = 200
    return resp
end

local function init(opts)

    if opts.is_master then
        box.schema.user.grant('guest',
            'read,write,execute',
            'universe',
            nil, { if_not_exists = true }
        )
    end

    local httpd = cartridge.service_get('httpd')

    if not httpd then
        return nil, err_httpd:new("not found")
    end

    -- assigning handler functions
	httpd:route(
        { path = '/storage/:login/update/:field', method = 'PUT', public = true },
        http_account_update
    )
    httpd:route(
        { path = '/storage/create', method = 'POST', public = true },
        http_account_add
    )
    httpd:route(
        { path = '/storage/:login/:field', method = 'GET', public = true },
        http_account_get
    )
    httpd:route(
        { path = '/storage/:login', method = 'DELETE', public = true },
        http_account_delete
    )

    return true
end

return {
    role_name = 'api',
    init = init,
    dependencies = {'cartridge.roles.vshard-router'},
}