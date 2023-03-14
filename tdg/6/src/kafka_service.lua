local log = require('log')
local json = require('json')

local connector = require('connector')

local function call(par)
    log.info(json.encode(par))
    connector.send("to_kafka", par, {})
    return "ok"
end

return {
    call = call,
}
