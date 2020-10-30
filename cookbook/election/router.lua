--
-- router.lua
-- A tarantool instance generating requests and forwarding them to the current
-- leader. Once the leader is dead, waits for a new leader to emerge among the
-- left alive instances, and continues forwarding requests to it.
--

netbox = require('net.box')
-- Log transactions and leader switches.
log = require('log')
fiber = require('fiber')

-- List of tarantool ports (ips) to connect to.
ports = {
    3301,
    3302,
    3303,
}

-- A helper returning number of set elements in a table.
function sizeof(tbl)
    local c = 0
    for k,v in pairs(tbl) do c = c + 1 end
    return c
end

-- Try to establish/reestablish connections to all the instances
-- listed in ports table.
function establish_connection(conns)
    log.info('Establishing connections...')
    for k, port in pairs(ports) do
        if conns[k] == nil then
            local conn = netbox.connect(port)
            if conn.state ~= 'error' then
                conns[k] = conn
                log.info('Connection to instance at '..port..' established')
            else
                log.info('Failed to connect to instance at '..port)
            end
        end
    end
    log.info('Connected to '..sizeof(conns)..' instances.')
end

-- Return a connection to an instance currently being the cluster leader.
function find_leader(conns)
    log.info('Looking for a new leader')
    local leader_conn = nil
    while not leader_conn do
        for k, conn in pairs(conns) do
            -- Determine leadership based on `box.info.election.state` output.
            local ok, is_leader = pcall(conn.eval, conn,
                                  'return box.info.election.state == \'leader\'')
            if ok then
                if is_leader then
                    leader_conn = conn
                    goto continue
                end
            else
                -- Connection to one of the instances is lost. Try to reconnect.
                log.info('No connection to '..conn.port)
                conns[k] = nil
                establish_connection(conns)
            end
        end
        -- Have some rest. Do not spam instances constantly while election is
        -- still in progress. None of them is leader yet.
        fiber.sleep(0.1)
        ::continue::
    end
    log.info('New leader found at '..leader_conn.port)
    return leader_conn
end

-- Insert some data to a synchronous space every now and then.
-- Once the leader dies, wait for a new leader to emerge and
-- continue relaying requests to it.
function  generate_data(conns)
    local leader_conn = find_leader(conns)
    for i = 1,1000 do
        ::retry::
        local ok, err = pcall(leader_conn.space.test.insert,
                              leader_conn.space.test, {i})
        log.info('test:insert{'..i..'} - '..(ok and 'success' or 'fail'))
        if not ok then
            log.info(err)
            -- Insertion failed. The leader is dead or reconfigured to voter.
            -- Wait for a new leader.
            leader_conn = find_leader(conns)
            goto retry
        end
        fiber.sleep(3)
    end
end

conns = {}
establish_connection(conns)
generate_data(conns)

