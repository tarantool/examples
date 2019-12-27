-- модуль проверки аргументов в функциях
local checks = require('checks')

local digest = require('digest')
local fiber = require('fiber')
local errors = require('errors')

local err_storage = errors.new_class("Storage error")

local SALT_LENGTH = 16

local function complete_table(major, minor)
    for k, v in pairs(major) do
        if minor[k] == nil then
            minor[k] = v
        end
    end
end

local function tuple_to_map(format, tuple)
    local map = {}
    for _, i in ipairs(format) do
        map[i.name] = tuple[i.name]
    end
    return map
end


local function generate_salt(length)
    return digest.base64_encode(
        digest.urandom(length - bit.rshift(length, 2)),
        {nopad=true, nowrap=true}
    ):sub(1, length)
end

local function password_digest(password, salt)
    return digest.pbkdf2(password, salt)
end

local function create_password(password)
    checks('string')

    local salt = generate_salt(SALT_LENGTH)

    local shadow = password_digest(password, salt)

    return {
        shadow = shadow,
        salt = salt,
    }
end

local function check_password(profile, password)
    checks('table', 'string')

    return profile.shadow == password_digest(password, profile.salt)
end

local function init_space()
    local profile = box.schema.space.create(
        'profile', -- имя спейса для хранения профилей 
        {
            -- формат хранимых кортежей
            format = {
                {'profile_id', 'unsigned'},
                {'bucket_id', 'unsigned'},
                {'first_name', 'string'},
                {'sur_name', 'string'},
                {'patronymic', 'string'},
                {'shadow','string'},
                {'salt', 'string'},
                {'msgs_count', 'unsigned'},
                {'service_info', 'string'}
            },

            -- создадим спейс, только если его не было
            if_not_exists = true,
        }
    )

    -- создадим индекс по id профиля
    profile:create_index('profile_id', {
        parts = {'profile_id'},
        if_not_exists = true,
    })

    profile:create_index('bucket_id', {
        parts = {'bucket_id'},
        unique = false,
        if_not_exists = true,
    })
end

local function profile_add(profile)
    checks('table')

    -- Проверяем существование пользователя с таким id
    local exist = box.space.profile:get(profile.profile_id)
    if exist ~= nil then
        return {ok = false, error = err_storage:new("Profile already exist")}
    end

    local password_data = create_password(profile.password)

    profile.shadow = password_data.shadow
    profile.salt = password_data.salt
    profile.password = nil
    box.space.profile:insert(box.space.profile:frommap(profile))

    return {ok = true, error = nil}
end

local function profile_update(id, password, changes)
    checks('number', 'string', 'table')
    
    local exists = box.space.profile:get(id)

    if exists == nil then
        return {profile = nil, error = err_storage:new("Profile not found")}
    end

    exists = tuple_to_map(box.space.profile:format(), exists)
    if not check_password(exists, password) then
        return {profile = nil, error = err_storage:new("Unauthorized")}
    end

    complete_table(exists, changes)
    if changes.password ~= nil then
        local password_data = create_password(changes.password)
        changes.shadow = password_data.shadow
        changes.salt = password_data.salt
        changes.password = nil
    end
    box.space.profile:replace(box.space.profile:frommap(changes))

    changes.bucket_id = nil
    changes.salt = nil
    changes.shadow = nil
    return {profile = changes, error = nil}
end

local function profile_get(id, password)
    checks('number', 'string')
    
    local profile = box.space.profile:get(id)
    if profile == nil then
        return {profile = nil, error = err_storage:new("Profile not found")}
    end

    profile = tuple_to_map(box.space.profile:format(), profile)
    if not check_password(profile, password) then
        return {profile = nil, error = err_storage:new("Unauthorized")}
    end
    
    profile.bucket_id = nil
    profile.shadow = nil
    profile.salt = nil
    return {profile = profile, error = nil}
end

local function profile_delete(id, password)
    checks('number', 'string')
    
    local exists = box.space.profile:get(id)
    if exists == nil then
        return {ok = false, error = err_storage:new("Profile not found")}
    end
    exists = tuple_to_map(box.space.profile:format(), exists)
    if not check_password(exists, password) then
        return {ok = false, error = err_storage:new("Unauthorized")}
    end

    box.space.profile:delete(id)
    return {ok = true, error = nil}
end

local function init(opts)
    if opts.is_master then
        init_space()

        box.schema.func.create('profile_add', {if_not_exists = true})
        box.schema.func.create('profile_get', {if_not_exists = true})
        box.schema.func.create('profile_update', {if_not_exists = true})
        box.schema.func.create('profile_delete', {if_not_exists = true})

        box.schema.role.grant('public', 'execute', 'function', 'profile_add', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'profile_get', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'profile_update', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'profile_delete', {if_not_exists = true})
    end

    rawset(_G, 'profile_add', profile_add)
    rawset(_G, 'profile_get', profile_get)
    rawset(_G, 'profile_update', profile_update)
    rawset(_G, 'profile_delete', profile_delete)

    return true
end

return {
    role_name = 'storage',
    init = init,
    utils = {
        profile_add = profile_add,
        profile_update = profile_update,
        profile_get = profile_get,
        profile_delete = profile_delete,
        create_password = create_password,
        password_digest = password_digest,
    },
    dependencies = {
        'cartridge.roles.vshard-storage'
    }
}
