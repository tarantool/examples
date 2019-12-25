local vshard = require('vshard')
local cartridge = require('cartridge')
local errors = require('errors')

local log = require('log')

local err_vshard_router = errors.new_class("Vshard routing error")
local err_httpd = errors.new_class("httpd error")

local function json_response(req, json, status) 
    local resp = req:render({json = json})
    resp.status = status
    return resp
end

local function internal_error_response(req, error)
    local resp = json_response(req, {
        info = "Internal error",
        error = error
    }, 500)
    return resp
end

local function profile_not_found_response(req)
    local resp = json_response(req, {
        info = "Profile not found"
    }, 404)
    return resp
end

local function profile_conflict_response(req)
    local resp = json_response(req, {
        info = "Profile already exist"
    }, 409)
    return resp
end

local function http_profile_add(req)
    local profile = req:json()

    local bucket_id = vshard.router.bucket_id(profile.profile_id)
    profile.bucket_id = bucket_id

    local ok, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'profile_add',
        {profile}
    )

    if error then
        return internal_error_response(req, error)
    end
    if not ok then
        return profile_conflict_response(req)
    end
    
    return json_response(req, {info = "Successfully created"}, 201)
end

local function http_profile_update(req)
    local profile_id = tonumber(req:stash('profile_id'))
    local new_profile = req:json()
    new_profile.profile_id = profile_id

    local bucket_id = vshard.router.bucket_id(profile_id)
    
    local profile, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'read',
        'profile_update',
        {profile_id, new_profile}
    )

    if error then
        return internal_error_response(req,error)
    end
    if profile == nil then
        return profile_not_found_response(req)
    end
    
    return json_response(req, profile, 200)
end

local function http_profile_get(req)
    local profile_id = tonumber(req:stash('profile_id'))

    local bucket_id = vshard.router.bucket_id(profile_id)

    local profile, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'read',
        'profile_get',
        {profile_id}
    )

    if error then
        return internal_error_response(req, error)
    end
    if profile == nil then
        return profile_not_found_response(req)
    end

    return json_response(req, profile, 200)
end

local function http_profile_delete(req)
    local profile_id = tonumber(req:stash('profile_id'))

    local bucket_id = vshard.router.bucket_id(profile_id)

    local ok, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'profile_delete',
        {profile_id}
    )

    if error then
        return internal_error_response(req, error)
    end
    if not ok then
        return profile_not_found_response(req)
    end

    return json_response(req, {info = "Deleted"}, 200)
end

local function init(opts)
    rawset(_G, 'vshard', vshard)

    if opts.is_master then
        box.schema.user.grant('guest',
            'read,write',
            'universe',
            nil, { if_not_exists = true }
        )
    end

    local httpd = cartridge.service_get('httpd')

    if not httpd then
        return nil, err_httpd:new("not found")
    end

    log.info("Starting httpd")
    -- Навешиваем функции-обработчики
    httpd:route(
        { path = '/profile', method = 'POST', public = true },
        http_profile_add
    )
    httpd:route(
        { path = '/profile/:profile_id', method = 'GET', public = true },
        http_profile_get
    )
    httpd:route(
        { path = '/profile/:profile_id', method = 'PUT', public = true },
        http_profile_update
    )
    httpd:route(
        {path = '/profile/:profile_id', method = 'DELETE', public = true},
        http_profile_delete
    )

    log.info("Created httpd")
    return true
end

return {
    role_name = 'api',
    init = init,
    dependencies = {
        'cartridge.roles.vshard-router'
    }
}
