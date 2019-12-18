local list = require('app.double_linked_list')

local lru_cache = {}

function lru_cache:get(key)
    local cache_item = self.cache[key]
    if cache_item ~= nil then
        -- popup key
        self.queue:remove(cache_item.queue_position)
        local new_position = self.queue:push(key)
        cache_item.queue_position = new_position

        return cache_item.item
    end
    return nil
end

function lru_cache:remove(key)
    assert(key~=nil)

    local cache_item = self.cache[key]
    if cache_item ~= nil then
        self.queue:remove(cache_item.queue_position)
        self.cache[key] = nil
        return true
    end
    return false
end

function lru_cache:set(key, item)
    assert(key~=nil)

    local to_return = nil
    if self.queue:is_full() then
        local stale_key, err = self.queue:pop()
        if err ~= nil then
            return nil, err
        end
        self.cache[stale_key] = nil
        to_return = stale_key
    end

    local queue_position, err = self.queue:push(key)
    if err ~= nil then
        return nil, err
    end

    local cache_item = {
        item = item,
        queue_position = queue_position,
    }
    self.cache[key] = cache_item

    return to_return
end

function lru_cache:is_empty()
    return self.queue:is_empty()
end

function lru_cache:is_full()
    return self.queue:is_full()
end

function lru_cache:filled()
    return self.queue.length
end

function lru_cache.new(max_length)
    assert(type(max_length) == 'number' and max_length > 0,
           "lru_cache.new(): Max length of cache must be a positive integer")

    local instance = {
        cache = {},
        queue = list.new(max_length),

        get = lru_cache.get,
        set = lru_cache.set,
        remove = lru_cache.remove,

        is_empty = lru_cache.is_empty,
        is_full = lru_cache.is_full,
        filled = lru_cache.filled,

    }

    return instance
end

return lru_cache
