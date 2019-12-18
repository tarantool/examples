local mysql = require('mysql')

local connection_pool = {}

function connection_pool:mysql_profile_get(id)
    local conn = self.pool:get()
    local tuples, ok = conn:execute("SELECT * FROM user_profile WHERE profile_id = ?", id)
    self.pool:put(conn)
    return tuples[1][1] -- Первый профиль
end

function connection_pool:mysql_profile_add(profile)
    local conn = self.pool:get()
    local ok = pcall(conn.execute, conn, "INSERT INTO user_profile VALUES(?,?,?,?,?,?,?);",
    profile.profile_id, profile.bucket_id, profile.first_name, profile.second_name, profile.patronymic, profile.msgs_count, profile.service_info)
    self.pool:put(conn)
    return ok
end

function connection_pool:mysql_profile_update(id, new_profile)
    local conn = self.pool:get()
    conn:begin()
    conn:execute("UPDATE user_profile SET "
            .."first_name = COALESCE(?, first_name),"
            .."second_name = COALESCE(?, second_name),"
            .."patronymic = COALESCE(?, patronymic),"
            .."msgs_count = COALESCE(?, msgs_count),"
            .."service_info = COALESCE(?, service_info)"
            .."WHERE profile_id = ?; ",
            new_profile.first_name, new_profile.second_name, new_profile.patronymic, new_profile.msgs_count, new_profile.service_info, id)
    local tuples, ok = conn:execute("SELECT * FROM user_profile where profile_id = ?;", id)
    if tuples[1][1] == nil then
        return nil
    end
    conn:commit()
    self.pool:put(conn)
    return tuples[1][1]
end 

function connection_pool:mysql_profile_delete(id)
    local conn = self.pool:get()
    local tuples, ok = conn:execute("SELECT * FROM user_profile where profile_id = ?", id)
    if tuples[1][1] ~= nil then
        tuples, ok = conn:execute("DELETE FROM user_profile WHERE profile_id = ?;", id)
    else
        ok = false
    end
    self.pool:put(conn)
    return ok
end

function connection_pool.new(opts)
    local instance = {
        -- Создаем пул соединений к базе
        pool = mysql.pool_create({
            host=opts.host, 
            user=opts.user, 
            password=opts.password, 
            db=opts.db,
            size=opts.size,
        }),
        profile_get = connection_pool.mysql_profile_get,
        profile_update = connection_pool.mysql_profile_update,
        profile_add = connection_pool.mysql_profile_add,
        profile_delete = connection_pool.mysql_profile_delete,
    }
    return instance
end
return connection_pool