local in_batches = require('cookbook.space.in_batches')

-- Say we need to change field type.
-- It's easy in the case of compatible types (ex. unsigned -> number):
-- just alter index definitions if any, and then change format.
-- However it gets trickier when values can not be casted automatically,
-- ex. casting between string, number, decimal,
-- or datetime (in the future Tarantool releases).
--
-- See `create_space` function for the space definition.
-- Three cases are covered below:
-- - field is not indexed,
-- - field is in the secondary index,
-- - field is the part of the primary key.
--
-- Note that running such migrations in production environments requires
-- application to work correctly in initial, final and every intermediate state.
-- So while migration is in process application must cast inserted/updated
-- values according to the current state, and use appropriate index values.
-- The latest can be automated with `key_def` module.
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

-- This is the simplest one.
-- Let's say we need to change type of `value` to `string`.
function examples.alter_not_indexed(space, batch_size)
    batch_size = batch_size or 100

    -- Change type to `any`, so we can store both string and numbers during migration.
    space:format({
        {'key', 'number'},
        {'value', 'any'},
    })

    -- Typecast all existing values.
    in_batches.atomic(batch_size, space:pairs(), function(tuple)
        space:update(tuple.key, {{'=', 'value', tostring(tuple.value)}})
    end)

    -- Update format to finish migration.
    space:format({
        {'key', 'number'},
        {'value', 'string'},
    })
end

-- With Tarantool 2.2+ it's possible to perform such migrations using
-- functional indexes. However it has limitation: function for index
-- must be sandboxed. If it's not the case proceed to `alter_pk`.
--
-- Let's say we need to change type of `value` to `string`, and
-- there is a secondary index (see `create_secondary_index`).
function examples.alter_indexed(space, batch_size)
    -- First, create an functional index on altered field,
    -- so it's possible to store values of both types at the same time.
    box.schema.func.create('migration_tostring', {
        is_deterministic = true,
        is_sandboxed = true,
        body = [[ function(tuple) return {tostring(tuple[2])} end ]],
    })
    space:create_index('secodary_new', {func = 'migration_tostring', parts = {{1, 'string'}}})

    -- Replace existing index with new one.
    space.index.secondary:drop()
    space.index.secodary_new:rename('secondary')

    -- Now it's possible to alter the field the same way as if it isn't indexed.
    examples.alter_not_indexed(space, batch_size)

    -- Finally, replace functional index with plain one and remove temporary function.
    space:create_index('secodary_new', {parts = {'value'}})
    space.index.secondary:drop()
    space.index.secodary_new:rename('secondary')
    box.func.migration_tostring:drop()
end

-- The most complicated case is when field is indexed but it's not possible
-- to change index to functional one.
--
-- Let's say we need to change type of `key` to `string`.
function examples.alter_pk(space, batch_size)
    batch_size = batch_size or 100

    -- First we need duplicate the altered field.
    -- Application must fill in the new field for inserted tuples as well,
    -- so actually this format can be applied at the bootstrap time.
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

    -- Now we can make `key_number` not-nullable and rebuild index using it.
    space:format({
        {'key', 'number'},
        {'value', 'number'},
        {'key_number', 'number'},
    })
    space.index.primary:alter({parts = {'key_number'}})

    -- Previous step makes it possible to set type `any` for the original field
    -- and typecast existing values.
    space:format({
        {'key', 'any'},
        {'value', 'number'},
        {'key_number', 'number'},
    })
    in_batches.atomic(batch_size, space:pairs(), function(tuple)
        space:update(tuple.key_number, {{'=', 'key', tostring(tuple.key)}})
    end)

    -- Update format and rebuild index using original field.
    space:format({
        {'key', 'string'},
        {'value', 'number'},
    })
    space.index.primary:alter({parts = {'key'}})

    -- Finally, remove temporary field from all tuples.
    in_batches.atomic(batch_size, space:pairs(), function(tuple)
        space:update(tuple.key, {{'#', 3, 1}})
    end)
end

return examples
