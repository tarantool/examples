--
-- Set up a simple synchronous replication master.
--
box.cfg{
    listen=3301,
    -- We usually use full-mesh topology even for master-replica installations.
    replication={3301,3302},
    -- Synchronous replication quorum. The transaction is committed only after
    -- being applied on two instances (master and replica).
    replication_synchro_quorum=2,
    -- A timeout to roll the transaction back in case the replica dies.
    replication_synchro_timeout=1,
}

box.once('init', function()
    -- Create a synchronous space.
    -- You may make an existing space synchronous or vice versa
    -- using `box.space.space_name:alter{is_sync=true/false}`
    box.schema.space.create('banking_data', {is_sync=true})
    box.space.banking_data:create_index('pk')
    box.schema.user.grant('guest', 'replication')
end)

-- For interactive console. Feel free to remove.
require('console').start()

