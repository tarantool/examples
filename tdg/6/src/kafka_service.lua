local log = require('log')
local json = require('json')
local repository = require('repository')

local connector = require('connector')

local function call(par)
    log.info("input: %s", json.encode(par))
    connector.send("to_kafka", par, {})
    return "ok"
end

local function processor(par)
    log.info("input: %s", json.encode(par))
    if next(par) and next(par.obj) and par.obj.id and par.obj.space_field_data then
        local data = {
            id = par.obj.id,
            space_field_data = par.obj.space_field_data
        }

        if par.obj.tokafka==true then
            connector.send("to_kafka", data, {})
        end
        if par.obj.tospase==true then
            local ok, err = repository.put('test_space', data)
            log.info("put answ: %s, err: %s", json.encode(ok), err)
        end
    else
        log.error("Broken data %s", json.encode(par.obj))
    end
    return true
end
return {
    call = call,
    processor = processor
}

