-- модуль проверки аргументов в функциях
local checks = require('checks')

-- модуль работы с mysql
local mysql = require('app.mysql_handlers')

-- lru кэш
local lru_cache = require('app.lru_cache')

-- модуль работы с числами
local decnumber = require('ldecnumber')

local cache = {}
local connection_pool = {}

local function init_cache(size)
    cache = lru_cache.new(size)
    for _, v in box.space.profile:pairs() do
        cache:set(v.profile_id, true)
    end
end

local function init_connection_pool(connection_count)
    connection_pool = mysql.new({
        host = '127.0.0.1',
        user = 'root',
        password = 'password',
        db = 'profile_storage',
        size = connection_count,
    })
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
                {'second_name', 'string'},
                {'patronymic', 'string'},
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
    -- Проверим что профиль уже существует
    local exists = cache:get(profile.profile_id)
    if exists then
        return false
    end

    local ok = connection_pool:profile_add(profile)
    if not ok then
        return false
    end
    
    box.space.profile:insert({
        profile.profile_id,
        profile.bucket_id,
        profile.first_name,
        profile.second_name,
        profile.patronymic,
        profile.msgs_count,
        profile.service_info
    })
    cache:set(profile.profile_id, true)
    return true
end

local function profile_update(id, changes)
    -- Проверка аргументов функции
    checks('number', 'table')

     -- Обновляем пользователя в базе
     local new_profile = connection_pool:profile_update(id, changes)
     if new_profile == nil then
         return nil
     end

    -- Обновляем профиль(или добавляем, если его не было в кеше)
    if cache:get(id) then
        box.space.profile:replace(box.space.profile:frommap(new_profile))
    else
        box.space.profile:insert(box.space.profile:frommap(new_profile))
        cache:set(id, true)
    end
    new_profile.bucket_id = nil
    return new_profile
end

local function profile_get(id)
    checks('number')
    
    local profile = nil
    local exists = cache:get(id)
    if exists then
        profile = box.space.profile:get(id)
    end

    -- Если нет в кеше, смотрим в базе
    if profile == nil then
        profile = connection_pool:profile_get(id)
        -- Если нашли в базе, добавляем в кэш
        if profile ~= nil then
            local prf = box.space.profile:frommap(profile)
            box.space.profile:insert(prf)
            cache:set(id, true)
            profile.bucket_id = nil
        end
    else
        profile = {
            profile_id = profile.profile_id,
            first_name = profile.first_name,
            second_name = profile.second_name,
            patronymic = profile.patronymic,
            msgs_count = profile.msgs_count,
            service_info = profile.service_info
        }
    end
    return profile
end

local function profile_delete(id)
    checks('number')
    
    local ok = connection_pool:profile_delete(id)
    if ok then
        box.space.profile:delete{id}
        cache:remove(id)
    end
    return ok
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

    init_connection_pool(5)
    init_cache(20)

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
