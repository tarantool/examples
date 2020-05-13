local in_batches = require('cookbook.space.in_batches')

-- Suppose we need to change a field type.
-- It's easy in case of compatible types (ex. unsigned -> number):
-- just alter index definitions, if any, and then change the format.
-- However it gets trickier when values cannot be cast automatically,
-- e.g. casting between string, number, decimal,
-- or datetime (to be supported in the upcoming Tarantool releases).
--
-- See the `create_space` function for space definition.
-- Three cases are covered below:
-- - field is not indexed,
-- - field is in the secondary index,
-- - field is part of the primary key.
--
-- Note that running such migrations in production environments requires the
-- application to work correctly in the initial, final, and every intermediate
-- state.
-- So while migration is in process, the application must cast inserted/updated
-- values according to the current state and use appropriate index values.
-- The latest can be automated with the `key_def` module.
--
-- Also index creation and altering is blocking before Tarantool 2.2,
-- so some of provided examples cannot be run without downtime in production
-- with earlier Tarantool versions.
local examples = {}

function examples.create_space(name)
    local space = box.schema.space.create(name or 'sample_space', {format = {
        {'key', 'number'},
        {'value', 'number'},
    }})
    space:create_index('primary', {parts = {'key'}})
    for i = 1, 1000 do
        space:insert({i, i})
    end
    return space
end

function examples.create_secondary_index(space)
    space:create_index('secondary', {parts = {'value'}})
end

-- This is the simplest case.
-- Suppose we need to change the type of `value` to `string`.
function examples.alter_not_indexed(space, batch_size)
    batch_size = batch_size or 100

    -- Change the type to `any`, so we can store both string and numbers during migration.
    space:format({
        {'key', 'number'},
        {'value', 'any'},
    })

    -- Typecast all existing values.
    in_batches.atomic(batch_size, space:pairs(), function(tuple)
        space:update(tuple.key, {{'=', 'value', tostring(tuple.value)}})
    end)

    -- Update the format to finish the migration.
    space:format({
        {'key', 'number'},
        {'value', 'string'},
    })
end

-- With Tarantool 2.2+ it's possible to perform such migrations using
-- functional indexes. However there is a limitation: the function for
-- the index must be sandboxed. If it's not the case, proceed to `alter_pk`.
--
-- Suppose we need to change the type of `value` to `string`, and
-- there is a secondary index (see `create_secondary_index`).
function examples.alter_indexed(space, batch_size)
    -- First, create a functional index on the altered field,
    -- so it's possible to store values of both types at the same time.
    box.schema.func.create('migration_tostring', {
        is_deterministic = true,
        is_sandboxed = true,
        body = [[ function(tuple) return {tostring(tuple[2])} end ]],
    })
    space:create_index('secodary_new', {func = 'migration_tostring', parts = {{1, 'string'}}})

    -- Replace the existing index with the new one.
    space.index.secondary:drop()
    space.index.secodary_new:rename('secondary')

    -- Now it's possible to alter the field as if it wasn't indexed.
    examples.alter_not_indexed(space, batch_size)

    -- Finally, replace the functional index with a plain one
    -- and remove the temporary function.
    space:create_index('secodary_new', {parts = {'value'}})
    space.index.secondary:drop()
    space.index.secodary_new:rename('secondary')
    box.func.migration_tostring:drop()
end

-- The most complicated case is when a field is indexed but it's not possible
-- to change the index type to functional.
--
-- Let's say we need to change the type of `key` to `string`.
function examples.alter_pk(space, batch_size)
    batch_size = batch_size or 100

    -- First, we need to duplicate the altered field.
    -- The application must fill in the new field for inserted tuples as well,
    -- so this format can actually be applied during bootstrap.
    space:format({
        {'key', 'number'},
        {'value', 'number'},
        {'key_number', 'number', is_nullable = true},
    })
    -- Fill in new field for all tuples.
    in_batches.atomic(batch_size, space:pairs(), function(tuple)
        if tuple.key_number == nil then
            space:update(tuple.key, {{'=', 'key_number', tuple.key}})
        end
    end)

    -- Now we can make `key_number` not-nullable and rebuild the index using it.
    space:format({
        {'key', 'number'},
        {'value', 'number'},
        {'key_number', 'number'},
    })
    space.index.primary:alter({parts = {'key_number'}})

    -- The previous step makes it possible to set the type `any` for the
    -- original field and typecast the existing values.
    space:format({
        {'key', 'any'},
        {'value', 'number'},
        {'key_number', 'number'},
    })
    in_batches.atomic(batch_size, space:pairs(), function(tuple)
        space:update(tuple.key_number, {{'=', 'key', tostring(tuple.key)}})
    end)

    -- Update the format and rebuild the index using the original field.
    space:format({
        {'key', 'string'},
        {'value', 'number'},
    })
    space.index.primary:alter({parts = {'key'}})

    -- Finally, remove the temporary field from all tuples.
    in_batches.atomic(batch_size, space:pairs(), function(tuple)
        space:update(tuple.key, {{'#', 3, 1}})
    end)
end

return examples
