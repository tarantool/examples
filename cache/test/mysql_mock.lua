local connection = {
	storage = {}
}

function connection:execute(request)
	local command = string.split(request, " ")[1]

	if command == "SELECT" then
		local login = string.split(request, "\'")[2]
		local account = self.storage[login]
		return {{account}}
	end

	if command == "REPLACE" then
		local data = string.split(request, "\'")
		self.storage[data[2]] = {
			login = data[2],
			password = data[4],
			bucket_id = tonumber(data[6]),
			name = data[8],
			email = data[10],
			last_action = data[12],
			data = data[14],
		}
		return 
	end

	if command == "DELETE" then 
		local login = string.split(request, "\'")[2]
		self.storage[login] = nil
		return
	end
end

function connection:begin()
	return nil
end

function connection:commit()
	return nil
end

function connection:rollback()

	self.storage = {}
	self.storage["Mura"] = {
        login = "Mura",
        password = "1243",
        bucket_id = 2,
        name = "Tom",
        email = "tom@mail.com",
        last_action = os.time(),
        data = "another secret"
    }

end

function connect(args)

	connection.storage["Mura"] = {
        login = "Mura",
        password = "1243",
        bucket_id = 2,
        name = "Tom",
        email = "tom@mail.com",
        last_action = os.time(),
        data = "another secret"
    }

    return connection
end

return { connect = connect;}