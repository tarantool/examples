local double_linked_list = {}

function double_linked_list:is_empty()
    return self.first == nil and self.last == nil
end

function double_linked_list:is_full()
    return self.length == self.max_length
end

function double_linked_list:insert(payload, after)
    if self:is_full() then
        return nil, 'List if full'
    end

    local item = {}
    item.payload = payload

    if after == nil then
        if self:is_empty() then
            self.first = item
            self.last = item
            item.prev = nil
            item.next = nil
        else
            local right = self.first

            right.prev = item
            item.next = right

            self.first = item
        end
    else
        if self:is_empty() then
            return nil, '`After` is invalid'
        end
        if self.first == self.last then
            assert(after == self.first)

            item.prev = self.first
            item.next = nil

            self.last = item
            self.first.next = item
        else
            local left = after
            local right = after.next

            left.next = item
            if right ~= nil then
                right.prev = item
            else
                self.last = item
            end
            item.prev = left
            item.next = right
        end
    end

    self.length = self.length + 1
    return item
end

function double_linked_list:remove(item)
    if self:is_empty() then
        return nil, 'List is empty'
    end

    if self.first == self.last then
        assert(self.first == item)

        self.first = nil
        self.last = nil
    else
        local left = item.prev
        local right = item.next

        if left == nil then
            right.prev = nil
            self.first = right
        elseif right == nil then
            left.next = nil
            self.last = left
        else
            left.next = right
            right.prev = left
        end
    end

    item.prev = nil
    item.next = nil

    self.length = self.length -1
    return item.payload
end


function double_linked_list:push(payload)
    return self:insert(payload, self.last)
end

function double_linked_list:pop()
    local payload, err = self:remove(self.first)
    if err ~= nil then
        return nil, err
    end
    return payload
end

function double_linked_list:clear()
    while not self:is_empty() do
        self:pop()
    end
end

function double_linked_list.new(max_length)
    assert(type(max_length) == 'number' and max_length > 0,
           "double_linked_list.new(): Max length of buffer must be a positive integer")

    local instance = {
        length = 0,
        first = nil,
        last = nil,

        max_length = max_length,
        is_empty = double_linked_list.is_empty,
        is_full = double_linked_list.is_full,
        clear = double_linked_list.clear,
        push = double_linked_list.push,
        pop = double_linked_list.pop,
        insert = double_linked_list.insert,
        remove = double_linked_list.remove,
    }

    return instance
end


return double_linked_list
