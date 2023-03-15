local connector = require('connector')

local function send_to_kafka(object, output_options)
    if not output_options then
        output_options = {}
    end
    connector.send("to_kafka", object, output_options)
end

return {
    send_to_kafka = send_to_kafka
}
