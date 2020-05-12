local fiber = require('fiber')

local export = {}

--- Run several iterations in a single transaction
--
-- This is useful in the following cases:
-- - improve the performance of write operations. Combining multiple operations
--   into a single transaction makes them produce a single WAL entry instead of
--   a WAL entry per each operation. In some scenarios this brings significant
--   improvement. But don't use large batch_size to not produce large
--   WAL entries which take long to write to disk.
-- - to keep an application responsive when processing large amounts of data.
--   Lua code runs in a single thread, so all long-running Lua fibers
--   block the other fibers. This can make the service irresponsive for seconds
--   or even minutes. The solution is to give control to other fibers
--   after several iterations.
--
-- @usage atomic(200, space:pairs(), function(tuple) space:update(...) end)
function export.atomic(batch_size, iter, fn)
    box.atomic(function()
        local i = 0
        for _, x in iter:unwrap() do
            fn(x)
            i = i + 1
            if i % batch_size == 0 then
                box.commit()
                fiber.yield() -- for read-only operations when `commit` doesn't yield
                box.begin()
            end
        end
    end)
end

--- Give control to other fibers after processing each batch of iterations
--
-- See the 2nd case in the `atomic` function.
--
-- @usage yield_every(1000, space:pairs()):filter(...):reduce(...)
-- @usage for _, tuple in yield_every(1000, space:pairs()) do ... end
function export.yield_every(batch_size, iter)
    local i = 0
    return iter:map(function(...)
        i = i + 1
        if i % batch_size == 0 then
            fiber.yield()
        end
        return ...
    end)
end

return export
