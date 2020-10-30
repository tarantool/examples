--
-- election.lua
-- An instance file for the three instances running leader election
-- based on RAFT together with synchronous replication.
-- To run the cluster create three identical files:
-- election1.lua, election2.lua, election3.lua
-- Run 3 tarantool instances from corresponding directories:
-- `tarantool election1.lua`
-- `tarantool election2.lua`
-- `tarantool election3.lua`
--
-- Determine this instance's id based on filename:
-- election1.lua -> 1
-- election2.lua -> 2
-- and so on.
local instance_id = string.match(arg[0], "%d")
-- This instance's listening port.
local port = 3300 + instance_id

box.cfg{
    listen=port,
    replication = {3301,3302,3303},
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
    -- send heartbeats for 4 * replication_timeout (4 seconds in our case).
    -- Once the leader is dead, remaining instances start a new election round.
    replication_timeout=1,
    -- Timeout between elections. Needed to restart elections when no leader
    -- emerges soon enough.
    election_timeout=1,
}

box.once('bootstrap', function()
    -- Grant the guest user replication rights.
    box.schema.user.grant('guest', 'replication')

    -- Create a synchronous space to enable synchronous replication
    -- for transactions touching this space.
    box.schema.space.create('test', {is_sync=true})
    box.space.test:create_index('pk')

    -- Grant rights for the router connection.
    box.schema.user.grant('guest', 'write', 'space', 'test')
    box.schema.user.grant('guest', 'execute', 'universe')
end)

-- For interactive console. Feel free to remove.
require('console').start()

