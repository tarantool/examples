local vshard = require('vshard')
local cartridge = require('cartridge')
local errors = require('errors')

local err_vshard_router = errors.new_class("Vshard routing error")
local err_httpd = errors.new_class("httpd error")

local function http_account_add(req)
    local time_stamp = os.clock()
    local account = req:json()
	local bucket_id = vshard.router.bucket_id(account.login)
    account.bucket_id = bucket_id

    local success, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'account_add',
        {account}
    )

    if error then
        local resp = req:render({json = {
            info = "Internal error",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 500
        return resp
    end

    if success == false then
    	local resp = req:render({json = {
            info = "Account with such login exists",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 409
        return resp
    end

    local resp = req:render({json = { info = "Account successfully created", time = os.clock() - time_stamp}})
    resp.status = 201
    return resp
end

local function http_account_sign_in(req)
    local time_stamp = os.clock()
	local login = req:stash('login')
	local password = req:json().password
	local bucket_id = vshard.router.bucket_id(login)

	local success, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'account_sign_in',
        {login, password}
    )

	if error then
        local resp = req:render({json = {
            info = "Internal error",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 500
        return resp
    end

    if success == nil then
    	local resp = req:render({json = {
            info = "Account not found",
            time = os.clock() - time_stamp,
            error = error
       	 }})
        resp.status = 404
        return resp
    end

    if success == false then
    	local resp = req:render({json = {
            info = "Wrong password",
            time = os.clock() - time_stamp,
            error = error,
       	 }})
        resp.status = 401
        return resp
    end

    local resp = req:render({json = { info = "Accepted", time = os.clock() - time_stamp}})
    resp.status = 202
    return resp

end

local function http_account_sign_out(req)
    local time_stamp = os.clock()
	local login = req:stash('login')
	local bucket_id = vshard.router.bucket_id(login)

	local success, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'account_sign_out',
        {login}
    )

    if success == nil then
    	local resp = req:render({json = {
            info = "Account not found",
            time = os.clock() - time_stamp,
            error = error
       	 }})
        resp.status = 404
        return resp
    end

	if error then
        local resp = req:render({json = {
            info = "Internal error",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 500
        return resp
    end

    local resp = req:render({json = { info = "Success", time = os.clock() - time_stamp}})
    resp.status = 200
    return resp

end


local function http_account_delete(req)
    local time_stamp = os.clock()
    local login = req:stash('login')
	local bucket_id = vshard.router.bucket_id(login)

	local success, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'read',
        'account_delete',
        {login}
    )

    if error then
        local resp = req:render({json = {
            info = "Internal error",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 500
        return resp
    end

    if success == nil then
        local resp = req:render({json = {
            info = "Account not found",
            time = os.clock() - time_stamp,
            error = error,
        }})
        resp.status = 404
        return resp
    end

    if success == false then
        local resp = req:render({json = {
            info = "Sign in first. Session is down",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 401
        return resp
    end

    local resp = req:render({json = {info = "Account deleted", time = os.clock() - time_stamp}})
    resp.status = 200
    return resp
end

local function http_account_update(req)
    local time_stamp = os.clock()
	local login = req:stash('login')
	local field = req:stash('field')
	local bucket_id = vshard.router.bucket_id(login)

	local value = req:json().value

	local success, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'account_update',
        {login, field, value}
    )

    if error then
        local resp = req:render({json = {
            info = "Internal error",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 500
        return resp
    end

    if success == nil then
        local resp = req:render({json = {
            info = "Account not found",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 404
        return resp
    end

    if success == false then
        local resp = req:render({json = {
            info = "Sign in first. Session is down",
            time = os.clock() - time_stamp,
        }})
        resp.status = 401
        return resp
    end

    if success == -1 then
        local resp = req:render({json = {
            info = "Invalid field",
            time = os.clock() - time_stamp,
        }})
        resp.status = 400
        return resp
    end

    local resp = req:render({json = {info = "Field updated", time = os.clock() - time_stamp}})
    resp.status = 200
    return resp
end

local function http_account_get(req)
    local time_stamp = os.clock()
	local login = req:stash('login')
	local field = req:stash('field')
	local bucket_id = vshard.router.bucket_id(login)

	local account_data, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'read',
        'account_get',
        {login, field}
    )

    if error then
        local resp = req:render({json = {
            info = "Internal error",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 500
        return resp
    end

    if account_data == nil then
        local resp = req:render({json = {
            info = "Account not found",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 404
        return resp
    end

    if account_data == false then
        local resp = req:render({json = {
            info = "Sign in first. Session is down",
            time = os.clock() - time_stamp,
        }})
        resp.status = 401
        return resp
    end

    if account_data == -1 then
        local resp = req:render({json = {
            info = "Invalid field",
            time = os.clock() - time_stamp,
        }})
        resp.status = 400
        return resp
    end

    local resp = req:render({json = {info = account_data, time = os.clock() - time_stamp}})
    resp.status = 200
    return resp
end

local function init(opts)
    rawset(_G, 'vshard', vshard)

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
        { path = '/storage/:login/sign_in', method = 'PUT', public = true },
        http_account_sign_in
    )
	httpd:route(
        { path = '/storage/:login/sign_out', method = 'PUT', public = true },
        http_account_sign_out
    )
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