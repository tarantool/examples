local param = ...
local threshold_date = param.threshold_date

local deleted_persons = repository.delete('Person', {{"$lastActivityDate", "<", threshold_date}})

local result = {}
for _, person in pairs(deleted_persons) do
    table.insert(result, {
        id=person.id,
        name=person.name,
        lastActivityDate=person.lastActivityDate
    })
end

return json.encode(result)
