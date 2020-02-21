local list = require('double_linked_list')

local lru_cache = {}

function lru_cache:update(key)
    local cache_item = self.cache[key]
    if cache_item ~= nil then
        -- popup key
        self.queue:remove(cache_item.queue_position)
        local new_position = self.queue:push(key)
        cache_item.queue_position = new_position

        return true
    end
    return false
end

function lru_cache:delete(key)
    local cache_item = self.cache[key]
    if cache_item ~= nil then
        -- popup key
        self.queue:remove(cache_item.queue_position)
        self.cache[key] = nil

        return true
    end
    return nil
end

function lru_cache:touch(key)
    assert(key~=nil)
    if self:update(key) then 
    	return true
    end

    local stale_key, err
    if self.queue:is_full() then
        stale_key, err = self.queue:pop()
        if err ~= nil then
            return nil, err
        end
        self.cache[stale_key] = nil
    end

    
    local queue_position, err = self.queue:push(key)
    if err ~= nil then
        return nil, err
    end

    local cache_item = {
        queue_position = queue_position,
    }
    self.cache[key] = cache_item

    if stale_key ~= nil then 
    	return stale_key
    end
    return true
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

        update = lru_cache.update,
        delete = lru_cache.delete,
        touch = lru_cache.touch,

        is_empty = lru_cache.is_empty,
        is_full = lru_cache.is_full,
        filled = lru_cache.filled,

    }

    return instance
end

return lru_cache
