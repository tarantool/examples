-- модуль проверки аргументов в функциях
local checks = require('checks')
local errors = require('errors')
-- класс ошибок дуступа к хранилищу профилей
local err_storage = errors.new_class("Storage error")
-- написанный нами модуль с функциями создания и проверки пароля
local auth = require('app.auth')

-- Функция преобразующая кортеж в таблицу согласно схеме хранения
local function tuple_to_table(format, tuple)
    local map = {}
    for i, v in ipairs(format) do
        map[v.name] = tuple[i]
    end
    return map
end

-- Функция заполняющая недостающие поля таблицы minor из таблицы major
local function complete_table(major, minor)
    for k, v in pairs(major) do
        if minor[k] == nil then
            minor[k] = v
        end
    end
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

    local password_data = auth.create_password(profile.password)

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

    exists = tuple_to_table(box.space.profile:format(), exists)
    if not auth.check_password(exists, password) then
        return {profile = nil, error = err_storage:new("Unauthorized")}
    end

    complete_table(exists, changes)
    if changes.password ~= nil then
        local password_data = auth.create_password(changes.password)
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

    profile = tuple_to_table(box.space.profile:format(), profile)
    if not auth.check_password(profile, password) then
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
    exists = tuple_to_table(box.space.profile:format(), exists)
    if not auth.check_password(exists, password) then
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
    },
    dependencies = {
        'cartridge.roles.vshard-storage'
    }
}
