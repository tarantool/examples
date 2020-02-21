#!/usr/bin/env tarantool

    local param = ...

    if param.obj.username ~= nil then
        param.routing_key = "add_user"
        return param
    end

    if param.obj.book_name ~= nil then
        param.routing_key = "add_book"
        return param
    end

    if (param.obj.user_id ~= nil and param.obj.book_id ~= nil) then
        param.routing_key = "add_subscription"
        return param
    end

    param.routing_key = "unknown_type"
    return param
