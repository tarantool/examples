-- Check version.
assert(_TARANTOOL >= '2.5.1', "Tarantool version 2.5.1+ supported")
--
-- Set up a synchronous replication replica
--
box.cfg{
    listen='127.0.0.1:3302',
    -- We usually use full-mesh topology even for master-replica installations.
    replication={'127.0.0.1:3301','127.0.0.1:3302'},
    -- Synchronous replication quorum. The transaction is committed only after
    -- being applied on two instances (master and replica).
    replication_synchro_quorum=2,
    -- A timeout to roll the transaction back in case the replica dies.
    replication_synchro_timeout=1,
    -- Safeguard. Only one synchronous replication master is
    -- supported currently.
    read_only=true,
}

-- For interactive console. Feel free to remove.
require('console').start()

