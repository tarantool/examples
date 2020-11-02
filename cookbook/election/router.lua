--
-- router.lua
-- A tarantool instance generating requests and forwarding them to the current
-- leader. Once the leader is dead, waits for a new leader to emerge among the
-- left alive instances, and continues forwarding requests to it.
--

local netbox = require('net.box')
-- Log transactions and leader switches.
local log = require('log')
local fiber = require('fiber')

local reconnect_interval = 0.1
local insertion_interval = 1

-- List of tarantool ports (ips) to connect to.
local ports = {
    3301,
    3302,
    3303,
}

local conns = {}
local leader_conn = nil
local leader_no = nil

local function connect(port)
    local conn = netbox.connect(port)
    if conn.state ~= 'error' then
        log.info('Connection to instance at '..port..' established')
        return conn
    end
    return nil
end

local function connection(id, port)
    conns[id] = connect(port)
    while true do
        fiber.sleep(reconnect_interval)
        if conns[id] == nil then
            conns[id] = connect(port)
        end
    end
end

local function set_leader(conns)
    while true do
        if leader_conn ~= nil then
            goto continue
        end
        for k, conn in pairs(conns) do
            local ok, is_leader = pcall(conn.eval, conn,
                                        [[return box.info.election.state == 'leader']])
            if ok then
                if is_leader then
                    leader_conn = conn
                    leader_no = k
                    log.info('Leader found at '..conn.port)
                    break
                end
            else
                log.info('No connection to instance at '..conn.port)
                conns[k] = nil
            end
        end
        ::continue::
        fiber.sleep(reconnect_interval)
    end
end

local function wait_leader()
    while leader_conn == nil do fiber.sleep(0.01) end
    return leader_no, leader_conn
end

-- Insert some data to a synchronous space every now and then.
-- Once the leader dies, wait for a new leader to emerge and
-- continue relaying requests to it.
local function  generate_data()
    local _, l_conn = wait_leader()
    for i = 1, 1000000 do
        local st = fiber.time()
        ::retry::
        local ok, err = pcall(l_conn.call, l_conn, "api_insert", {i})
        log.info('test:insert{'..i..'} - '..(ok and 'success' or 'fail'))
        if not ok then
            log.info(err)
            -- Insertion failed. The leader is dead or reconfigured to voter.
            -- Wait for a new leader.
            leader_conn = nil
            _, l_conn = wait_leader()
            goto retry
        end
        log.info('{'..i..'} took '..fiber.time()-st..' seconds')
        fiber.sleep(insertion_interval)
    end
end

local workers = {}
for k, port in pairs(ports) do
    workers[k] = fiber.new(connection, k, port)
end

local leader_f = fiber.new(set_leader, conns)

generate_data()

os.exit()

