local get_calls_count = 0
local add_calls_count = 0
local update_calls_count = 0
local delete_calls_count = 0

-- Значение возвращаемое из функций заглушек
local retvalue = nil

local function set_retvalue(value)
    retvalue = value
end

-- Количество вызовов функций заглушек
local function calls_count()
    return get_calls_count + add_calls_count + update_calls_count + delete_calls_count
end

local function profile_get(self, id)
    get_calls_count = get_calls_count + 1
    return retvalue
end

local function profile_add(self, profile)
    add_calls_count = add_calls_count + 1
    return retvalue
end

local function profile_update(self, id, new_profile)
    update_calls_count = update_calls_count + 1
    return retvalue
end

local function profile_delete(self, id)
    delete_calls_count = delete_calls_count + 1
    return retvalue
end

local function new(conn_count)
    local instance =  {
        profile_get = profile_get,
        profile_add = profile_add,
        profile_update = profile_update,
        profile_delete = profile_delete,
    }
return instance
end

return {
    new = new,
    set_retvalue = set_retvalue,
    calls_count = calls_count
}
