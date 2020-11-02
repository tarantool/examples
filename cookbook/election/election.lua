--
-- election.lua
-- An instance file for the three instances running leader election
-- based on RAFT together with synchronous replication.
--

-- Check tarantool version.
assert(_TARANTOOL >= '2.6.1', 'tarantool 2.6.1+ required')

local instance_id = string.match(arg[1], '^%d+$')
assert(instance_id, 'malformed instance id')

-- This instance's listening port.
local port = 3300 + instance_id
-- Thid instance's working directory.
local workdir = 'tnt'..instance_id
local fio = require('fio')
if not fio.path.exists(workdir) then
    local ok, err = fio.mkdir(workdir)
    assert(ok, "Failed to create working directory "..workdir)
end

local fiber = require('fiber')

box.cfg{
    wal_dir=workdir,
    memtx_dir=workdir,

    instance_uuid='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa'..instance_id,

    listen='127.0.0.1:'..port,
    replication = {
        '127.0.0.1:'..3301,
        '127.0.0.1:'..3302,
        '127.0.0.1:'..3303,
    },
    replication_connect_quorum=0,

    -- The instance is set to candidate, so it may become leader itself
    -- as well as vote for other instances.
    --
    -- Alternative: set one of the three instances to `voter`, so that it
    -- never becomes a leader but still votes for one of its peers and helps
    -- it reach election quorum (2 in our case).
    election_mode='candidate',
    -- Quorum for both synchronous transactions and
    -- leader election votes.
    replication_synchro_quorum=2,
    -- Synchronous replication timeout. The transaction will be
    -- rolled back if no quorum is achieved during 1 second.
    replication_synchro_timeout=1,
    -- Heartbeat timeout. A leader is considered dead if it doesn't
    -- send heartbeats for 4 * replication_timeout (1 second in our case).
    -- Once the leader is dead, remaining instances start a new election round.
    replication_timeout=0.25,
    -- Timeout between elections. Needed to restart elections when no leader
    -- emerges soon enough.
    election_timeout=0.25,
}

function api_insert(key)
    return box.space.test:insert{fiber.time64() / 1e4, key}
end

box.once('bootstrap', function()
    -- Grant the guest user replication rights.
    box.schema.user.grant('guest', 'replication')

    -- Create a synchronous space to enable synchronous replication
    -- for transactions touching this space.
    box.schema.space.create('test', {is_sync=true})
    box.space.test:format({
        {name='timestamp', type='scalar'},
        {name='iteration', type='unsigned'}
    })
    box.space.test:create_index('pk', {unique=true, parts={'timestamp', 'iteration'}})

    -- Grant rights for the router connection.
    box.schema.user.grant('guest', 'write', 'space', 'test')
    box.schema.user.grant('guest', 'execute', 'universe')
end)

-- For interactive console. Feel free to remove.
require('console').start()

