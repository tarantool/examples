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

function export.example(batch_size, space_name)
    batch_size = batch_size or 100

    -- Create space and add initial data.
    local space = box.schema.space.create(space_name or 'in_batches_example')
    space:format({
        {'key', 'number'},
        {'value', 'number'},
    })
    space:create_index('primary', {parts = {'key'}})
    for i = 1, 1010 do space:insert({i, i}) end

    -- Helper function to print the number of yields, to ensure that they actually occur.
    local function count_yields(fn)
        local yields = 0
        local counter = fiber.new(function()
            while true do
                fiber.yield()
                yields = yields + 1
            end
        end)
        local result = fn()
        counter:cancel()
        print('yielded: ' .. yields)
        return result
    end

    -- Use `atomic` to update all tuples.
    --
    -- It yields once for every batch and one more time for the last partial batch.
    -- Same as `math.ceil(count / batch_size)`
    --
    -- However, there can be more yields because multiple ones may occur during
    -- long WAL write.
    count_yields(function()
        export.atomic(batch_size, space:pairs(), function(tuple)
            space:update(tuple.key, {{'=', 'value', math.random(10)}})
        end)
    end)


    -- Here is an analog of the SQL query:
    --      SELECT value, COUNT(*)
    --      FROM space
    --      WHERE MOD(key % 100) != 0
    --      GROUP BY value
    --
    -- As the query is read-only, we can use `yield_every` with a chain
    -- of iterator transformations.
    --
    -- It yields only `math.floor(count / batch_size)` times because there is
    -- no yield after the final partial batch.
    return count_yields(function()
        return export.yield_every(batch_size, space:pairs()):
            filter(function(tuple) return tuple.key % 100 ~= 0 end):
            reduce(function(acc, tuple)
                acc[tuple.value] = (acc[tuple.value] or 0) + 1
                return acc
            end, {})
    end)
end

return export
