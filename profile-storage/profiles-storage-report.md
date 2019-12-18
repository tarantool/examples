# Хранилище профилей на Tarantool Cartridge

## Задачи 
 * Написать приложение для Tarantool Cartridge предоставляющее API со следующими функциями
   1. Добавление профиля по POST /profile
   2. Обновление данных профиля PUT /profile/id
   3. Получение данных о профиле GET /profile/id
   4. Удаление профиля DELETE /profile/id
 * Реализовать LRU `write through` кэш на Tarantool и MySQL 

## О хранимых данных
В данных профиля будем хранить следующую информацию:
* ФИО
* Количество отправленных писем
* Сервисная информация

## Хранилище MySQL

Опишем структуру данных в `init.sql`

```sql
CREATE TABLE IF NOT EXISTS user_profile (
    profile_id integer unsigned primary key,
    bucket_id integer unsigned,
    first_name varchar(20),
    second_name varchar(20),
    patronymic varchar(20),
    msgs_count integer unsigned,
    service_info varchar(20)
);
```

Запустим интерфейс командной строки MySQL
```bash
you@yourmachine$ mysql -u root 
```

Создадим пользователя, который будет взаимодействовать с базой данных, и настроим авторизацию по паролю
```mysql
mysql> CREATE USER 'tarantool-user'@'%' IDENTIFIED BY 'password';
mysql> GRANT CREATE ON * TO 'tarantool-user'@'%';
```

Подключимся к MySQL с помощью пользователя `tarantool-user`
```bash
you@yourmachine$ mysql -u tarantool-user -p
```

Создадим новую базу данных в MySQL и создадим в ней таблицу для профилей.
```mysql
mysql> CREATE DATABASE profile_storage;
mysql> USE profile_storage;
mysql> source init.sql
```

Готово! Теперь приступим к реализации приложения на Tarantool Cartridge

## Подготовка
Создадим новый проект
```bash
you@yourmachine $ cartridge create --name profiles-storage .
```

## LRU cache

Будем использовать LRU(Least Reacently Used) модель вытеснения записей. Для эффективного определения элемента, который должен быть удален реализуем структуру lru-cache. Принцип ее работы следующий: имеется двусвязный список - очередь, элементы в очереди отсортированы в зависимости от времени последнего обращения - чем ближе к голове очереди, тем дольше элемент не использовался. При повторном использовании элемент извлекается из очереди и добавляется в конец. При добавлении нового элемента в кэш, он также добавляется в конец очереди, если размер очереди становится больше порогового, то извлекается элемент из ее головы. Для быстрого нахождения позиции элемента в очереди используем таблицу ключ-значение.

### Модуль свзязного списка
Создадим модуль `app/double_linked_list.lua` и реализуем в нем двусвязный список

```lua
-- double_linked_list.lua

local double_linked_list = {}

function double_linked_list:is_empty()
    return self.first == nil and self.last == nil
end

function double_linked_list:is_full()
    return self.length == self.max_length
end

function double_linked_list:insert(payload, after)
    if self:is_full() then
        return nil, 'List is full'
    end

    local item = {}
    item.payload = payload

    if after == nil then
        if self:is_empty() then
            self.first = item
            self.last = item
            item.prev = nil
            item.next = nil
        else
            local right = self.first

            right.prev = item
            item.next = right

            self.first = item
        end
    else
        if self:is_empty() then
            return nil, 'After is invalid'
        end
        if self.first == self.last then
            assert(after == self.first)

            item.prev = self.first
            item.next = nil

            self.last = item
            self.first.next = item
        else
            local left = after
            local right = after.next

            left.next = item
            if right ~= nil then
                right.prev = item
            else
                self.last = item
            end
            item.prev = left
            item.next = right
        end
    end

    self.length = self.length + 1
    return item
end

function double_linked_list:remove(item)
    if self:is_empty() then
        return nil, 'List is empty'
    end

    if self.first == self.last then
        assert(self.first == item)

        self.first = nil
        self.last = nil
    else
        local left = item.prev
        local right = item.next

        if left == nil then
            right.prev = nil
            self.first = right
        elseif right == nil then
            left.next = nil
            self.last = left
        else
            left.next = right
            right.prev = left
        end
    end

    item.prev = nil
    item.next = nil

    self.length = self.length -1
    return item.payload
end


function double_linked_list:push(payload)
    return self:insert(payload, self.last)
end

function double_linked_list:pop()
    local payload, err = self:remove(self.first)
    if err ~= nil then
        return nil, err
    end
    return payload
end

function double_linked_list:clear()
    while not self:is_empty() do
        self:pop()
    end
end

function double_linked_list.new(max_length)
    assert(type(max_length) == 'number' and max_length > 0,
           "double_linked_list.new(): Max length of buffer must be a positive integer")

    local instance = {
        length = 0,
        first = nil,
        last = nil,

        max_length = max_length,
        is_empty = double_linked_list.is_empty,
        is_full = double_linked_list.is_full,
        clear = double_linked_list.clear,
        push = double_linked_list.push,
        pop = double_linked_list.pop,
        insert = double_linked_list.insert,
        remove = double_linked_list.remove,
    }

    return instance
end
```

### Модуль LRU cache

Теперь на основе связного списка реализуем `lru-cache`

```lua
-- lru_cache.lua

local list = require('app.double_linked_list')

local lru_cache = {}

function lru_cache:get(key)
    local cache_item = self.cache[key]
    if cache_item ~= nil then
        self.queue:remove(cache_item.queue_position)
        local new_position = self.queue:push(key)
        cache_item.queue_position = new_position

        return cache_item.item
    end
    return nil
end

function lru_cache:remove(key)
    assert(key~=nil)

    local cache_item = self.cache[key]
    if cache_item ~= nil then
        self.queue:remove(cache_item.queue_position)
        self.cache[key] = nil
        return true
    end
    return false
end

function lru_cache:set(key, item)
    assert(key~=nil)

    local to_return = nil
    if self.queue:is_full() then
        local stale_key, err = self.queue:pop()
        if err ~= nil then
            return nil, err
        end
        self.cache[stale_key] = nil
        to_return = stale_key
    end

    local queue_position, err = self.queue:push(key)
    if err ~= nil then
        return nil, err
    end

    local cache_item = {
        item = item,
        queue_position = queue_position,
    }
    self.cache[key] = cache_item

    return to_return
end

function lru_cache:is_empty()
    return self.queue:is_empty()
end

function lru_cache:is_full()
    return self.queue:is_full()
end

function lru_cache:filled()
    return self.queue.length
end

function lru_cache.new(max_length)
    assert(type(max_length) == 'number' and max_length > 0,
           "lru_cache.new(): Max length of cache must be a positive integer")

    local instance = {
        cache = {},
        queue = list.new(max_length),

        get = lru_cache.get,
        set = lru_cache.set,
        remove = lru_cache.remove,

        is_empty = lru_cache.is_empty,
        is_full = lru_cache.is_full,
        filled = lru_cache.filled,

    }

    return instance
end

return lru_cache
```

## Реализация бизнес-логики

### MySQL хендлеры

В модуле `app/mysql_handlers.lua` реализуем функции, осуществляющие добавление, удаление, обновление и чтение профиля пользователя из MySQL базы данных 

```lua
-- модуль работы с mysql
local mysql = require('mysql')
local connection_pool = {}
```

3. Функция добавления нового профиля в MySQL
```lua
function connection_pool:mysql_profile_add(profile)
    local conn = self.pool:get()
    local ok = pcall(conn.execute, conn, "INSERT INTO user_profile VALUES(?,?,?,?,?,?,?);",
    profile.profile_id, profile.bucket_id, profile.first_name, profile.second_name, 
    profile.patronymic, profile.msgs_count, profile.service_info)
    self.pool:put(conn)
    return ok
end
```

4. Функция обновления профиля в MySQL
```lua
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
            new_profile.first_name, new_profile.second_name, new_profile.patronymic,
            new_profile.msgs_count, new_profile.service_info, id)
    local tuples, ok = conn:execute("SELECT * FROM user_profile where profile_id = ?;", id)
    if tuples[1][1] == nil then
        return nil
    end
    conn:commit()
    self.pool:put(conn)
    return tuples[1][1]
end 
```

5. Функция удаления профиля в MySQL
```lua
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
```

6. Функция получения профиля из MySQL
```lua
function connection_pool:mysql_profile_get(id)
    local conn = self.pool:get()
    local tuples, ok = conn:execute("SELECT * FROM user_profile WHERE profile_id = ?", id)
    self.pool:put(conn)
    return tuples[1][1]
end
```

7. Функция создания нового пула подключений
```lua
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
```
8. Экспортируем модуль
```lua
return connection_pool
```

### Роль storage

Реализуем роль, которая инициализирует хранилище и реализует функции доступа к данным.

Создадим новый файл, где и реализуем эту роль
```bash
profiles-storage $ touch app/roles/storage.lua
```

1. Подключим необходимые модули:
```lua
-- модуль проверки аргументов в функциях
local checks = require('checks')

local lru_cache = require('app.lru_cache')
local mysql = require('app.mysql_handlers')

-- модуль работы с числами
local decnumber = require('ldecnumber')

local cache = {}
local connection_pool = {}
```

1. Функция инциализации кэша
```lua
local function init_cache(size)
    cache = lru_cache.new(size)
    for _, v in box.space.profile:pairs() do
        cache:set(v.profile_id, true)
    end
end
```

1. Инциализация подключения к MySQL
```lua
local function init_connection_pool(connection_count)
    connection_pool = mysql.new({
        host = '127.0.0.1',
        user = 'tarantool-user',
        password = 'password',
        db = 'profile_storage',
        size = connection_count,
    })
end
```

2. Инициализацию необходимого пространства в хранилище
```lua
local function init_space()
    local profile = box.schema.space.create(
        'profile', -- имя спейса для хранения профилей 
        {
            -- формат хранимых кортежей
            format = {
                {'profile_id', 'unsigned'},
                {'bucket_id', 'unsigned'},
                {'first_name', 'string'},
                {'second_name', 'string'},
                {'patronymic', 'string'},
                {'msgs_count', 'unsigned'},
                {'service_info', 'string'}
            },

            -- создадим спейс, только если его не было
            if_not_exists = true,
        }
    )

    -- создадим индекс по id профиля
    profile:create_index('profile_id', {
        parts = {'profile_id'},
        if_not_exists = true,
    })

    profile:create_index('bucket_id', {
        parts = {'bucket_id'},
        unique = false,
        if_not_exists = true,
    })
end
```

3. Функция добавления нового профиля
```lua
local function profile_add(profile)
    -- Проверим что профиль уже существует
    local exists = cache:get(profile.profile_id)
    if exists then
        return false
    end

    local ok = connection_pool:profile_add(profile)
    if not ok then
        return false
    end
    
    box.space.profile:insert({
        profile.profile_id,
        profile.bucket_id,
        profile.first_name,
        profile.second_name,
        profile.patronymic,
        profile.msgs_count,
        profile.service_info
    })
    cache:set(profile.profile_id, true)
    return true
end
```

4. Функция обновления профиля
```lua
local function profile_update(id, changes)
    -- Проверка аргументов функции
    checks('number', 'table')

     -- Обновляем пользователя в базе
     local new_profile = connection_pool:profile_update(id, changes)
     if new_profile == nil then
         return nil
     end

    print(new_profile.msgs_count)
    -- Обновляем профиль(или добавляем, если его не было в кеше)
    if cache:get(id) then
        box.space.profile:replace(box.space.profile:frommap(new_profile))
    else
        box.space.profile:insert(box.space.profile:frommap(new_profile))
        cache:set(id, true)
    end
    new_profile.bucket_id = nil
    return new_profile
end
```

5. Функция получения информации о профиле
```lua
local function profile_get(id)
    checks('number')
    
    local profile = nil
    local exists = cache:get(id)
    if exists then
        profile = box.space.profile:get(id)
    end

    -- Если нет в кеше, смотрим в базе
    if profile == nil then
        profile = connection_pool:profile_get(id)
        -- Если нашли в базе, добавляем в кэш
        if profile ~= nil then
            local prf = box.space.profile:frommap(profile)
            box.space.profile:insert(prf)
            cache:set(id, true)
            profile.bucket_id = nil
        end
    else
        profile = {
            profile_id = profile.profile_id,
            first_name = profile.first_name,
            second_name = profile.second_name,
            patronymic = profile.patronymic,
            msgs_count = profile.msgs_count,
            service_info = profile.service_info
        }
    end
    return profile
end
```

6. Функция удаления профиля
```lua
local function profile_delete(id)
    checks('number')
    
    local ok = connection_pool:profile_delete(id)
    if ok then
        box.space.profile:delete{id}
        cache:remove(id)
    end
    return ok
end
```

7. Функция инициализации роли
```lua
local function init(opts)
    if opts.is_master then
        init_space()

        box.schema.func.create('profile_add', {if_not_exists = true})
        box.schema.func.create('profile_get', {if_not_exists = true})
        box.schema.func.create('profile_update', {if_not_exists = true})
        box.schema.func.create('profile_delete', {if_not_exists = true})

        box.schema.role.grant('public', 'execute', 'function', 'profile_add', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'profile_get', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'profile_update', {if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'profile_delete', {if_not_exists = true})
    end

    init_connection_pool(5)
    init_cache(20)

    rawset(_G, 'profile_add', profile_add)
    rawset(_G, 'profile_get', profile_get)
    rawset(_G, 'profile_update', profile_update)
    rawset(_G, 'profile_delete', profile_delete)

    return true
end
```

8. Экспортируем функции роли и зависимости из модуля
```lua
return {
    role_name = 'storage',
    init = init,
    utils = {
        profile_add = profile_add,
        profile_update = profile_update,
        profile_get = profile_get,
        profile_delete = profile_delete,
    },
    dependencies = {
        'cartridge.roles.vshard-storage'
    }
}
```

Первая роль готова!

### Роль api

1. Подключим необходимые модули
```lua
local vshard = require('vshard')
local cartridge = require('cartridge')
local errors = require('errors')
```

2. Создадим классы ошибок
```lua
local err_vshard_router = errors.new_class("Vshard routing error")
local err_httpd = errors.new_class("httpd error")
```

3. Обработчик http-запроса на добавление профиля
```lua
local function http_profile_add(req)
    local profile = req:json()

    local bucket_id = vshard.router.bucket_id(profile.profile_id)

    local ok, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'profile_add',
        {profile}
    )

    if error then
        local resp = req:render({json = {
            info = "Internal error",
            error = error
        }})
        resp.status = 500
        return resp
    end
    if not ok then
        local resp = req:reder({json = {
            info = "Profile already exist"
        }})
        resp.status = 409
        return resp
    end
    
    local resp = req:render({json = {info = "Successfully created"}})
    resp.status = 201
    return resp
end
```

4. Обработчик http-запроса на изменение профиля
```lua
local function http_profile_update(req)
    local profile_id = tonumber(req:stash('profile_id'))
    local new_profile = req:json()
    new_profile.profile_id = profile_id

    local bucket_id = vshard.router.bucket_id(profile_id)
    
    local profile, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'read',
        'profile_update',
        {profile_id, new_profile}
    )

    if error then
        local resp = req:render({json = {
            info = "Internal error",
            error = error
        }})
        resp.status = 500
        return resp
    end
    if profile == nil then
        local resp = req:render({json = {
            info = "Profile not found"
        }})
        resp.status = 404
        return resp
    end
    
    local resp = req:render({json = profile})
    resp.status = 200
    return resp
end
```

5. Обработчик http-запроса на получение профиля
```lua
local function http_profile_get(req)
    local profile_id = tonumber(req:stash('profile_id'))

    local bucket_id = vshard.router.bucket_id(profile_id)

    local profile, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'read',
        'profile_get',
        {profile_id}
    )

    if error then
        local resp = req:render({json = {
            info = "Internal error",
            error = error
        }})
        resp.status = 500
        return resp
    end
    if profile == nil then
        local resp = req:render({json = {
            info = "Profile not found"
        }})
        resp.status = 404
        return resp
    end

    local resp = req:render({json = profile})
    resp.status = 200
    return resp
end
```

6. Обработчик http-запроса на удаление профиля
```lua
local function http_profile_delete(req)
    local profile_id = tonumber(req:stash('profile_id'))

    local bucket_id = vshard.router.bucket_id(profile_id)

    local ok, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'profile_delete',
        {profile_id}
    )

    if error then
        local resp = req:render({json = {
            info = "Internal error",
            error = error
        }})
        resp.status = 500
        return resp
    end
    if ok == nil then
        local resp = req:render({json = {
            info = "Profile not found"
        }})
        resp.status = 404
        return resp
    end

    local resp = req:render({json = {
        info = "Deleted"
    }})
    resp.status = 200
    return resp
end
```

7. Инициализация роли
```lua
local function init(opts)
    rawset(_G, 'vshard', vshard)

    if opts.is_master then
        box.schema.user.grant('guest',
            'read,write',
            'universe',
            nil, { if_not_exists = true }
        )
    end

    local httpd = cartridge.service_get('httpd')

    if not httpd then
        return nil, err_httpd:new("not found")
    end

    -- Навешиваем функции-обработчики
    httpd:route(
        { path = '/profile', method = 'POST', public = true },
        http_profile_add
    )
    httpd:route(
        { path = '/profile/:profile_id', method = 'GET', public = true },
        http_profile_get
    )
    httpd:route(
        { path = '/profile/:profile_id', method = 'PUT', public = true },
        http_profile_update
    )
    httpd:route(
        {path = '/profile/:profile_id', method = 'DELETE', public = true},
        http_profile_delete
    )

    return true
end
```

8. Экспортируем функции роли и зависимости из модуля
```lua
return {
    role_name = 'api',
    init = init,
    dependencies = {
        'cartridge.roles.vshard-router'
    }
}
```

## Добавление зависимостей

Пропишем новые роли в `init.lua` в корне проекта:
```lua
local ok, err = cartridge.cfg({
    workdir = 'tmp/db',
    roles = {
        'cartridge.roles.vshard-storage',
        'cartridge.roles.vshard-router',
        'app.roles.api',
        'app.roles.storage'
    },
    cluster_cookie = 'profiles-storage-cluster-cookie',
})
```
Также мы в наших ролях использовали некоторые внешние модули. Их необходимо добавить в список зависимостей в файл `profiles-storage-scm-1.rockspec`.

```conf
package = 'profiles-storage'
version = 'scm-1'
source  = {
    url = '/dev/null',
}
-- Put any modules your app depends on here
dependencies = {
    'tarantool',
    'lua >= 5.1',
    'luatest == 0.3.0-1',
    'cartridge == 1.2.0-1',
    'ldecnumber == 1.1.3-1',
}
build = {
    type = 'none';
}
```

## Тестирование

Напишем модульные и интеграционные тесты, проверяющие правильность работы нашего приложения. Для написания тестов будем использовать `luatest`.

### Модульные тесты

Протестируем правильность работы отдельных модулей нашего приложения. Файлы модульных тестов располагаются в папке `test/unit`

Cоздадим файл `double_linked_list_test.lua`, в нем опишем тесты для связного списка.

```lua
-- double_linked_list_test.lua
local t = require('luatest')
local g = t.group('unit_double_linked_list')
local linked_list = require('app.double_linked_list')

require('test.helper.unit')

g.test_new = function()
    local list = linked_list.new(2)

    t.assert_equals(type(list), 'table')
    t.assert_equals(list:is_empty(), true)
end

g.test_push_pop_ok = function()
    local list = linked_list.new(1)

    list:push(1)
    
    t.assert_equals(list:is_empty(), false)
    t.assert_equals(list:is_full(), true)
    t.assert_equals(list:pop(), 1)
    t.assert_equals(list:is_empty(), true)
end

g.test_push_pop_fail = function()
    local list = linked_list.new(2)

    list:push(1)
    list:push(2)
    local item, err = list:push(3)

    t.assert_equals(item, nil)
    t.assert_equals(err, 'List is full')

    list:pop()
    list:pop()
    local payload, err = list:pop()

    t.assert_equals(payload, nil)
    t.assert_equals(err, 'List is empty')
end

g.test_insert_remove_ok = function()
    local list = linked_list.new(3)

    local item1 = list:insert(1, nil)
    local item2 = list:insert(2, nil)
    local item3 = list:insert(3, item2)

    t.assert_equals(list:is_full(), true)
    t.assert_equals(list:remove(item1), 1)
    t.assert_equals(list:remove(item2), 2)
    t.assert_equals(list:pop(), 3)
end

g.test_insert_remove_fail = function()
    local list = linked_list.new(2)

    local item1 = list:insert(1, nil)
    local item2 = list:insert(2, nil)
    local item, err = list:insert(3, item2)

    t.assert_equals(item, nil)
    t.assert_equals(err, 'List is full')

    list:remove(item2)
    list:remove(item1)

    local payload, err = list:remove(item2)
    
    t.assert_equals(payload, nil)
    t.assert_equals(err, 'List is empty')

    item, err = list:insert(1, item1)

    t.assert_equals(item, nil)
    t.assert_equals(err, 'After is invalid')
end

g.test_clear = function()
    local list = linked_list.new(5)

    for i = 0, 5, 1 do
        list:push(i)
    end

    list:clear()

    t.assert_equals(list:is_empty(), true)

    for i = 5, 1, -1 do
        list:push(i)
    end

    t.assert_equals(list:pop(), 5)
end
```

Тесты для кэша опишем в файле `lru_cache_test.lua`

```lua
-- lru_cache_test.lua
local t = require('luatest')
local g = t.group('unit_lru_cache')
local lru_cache = require('app.lru_cache')

require('test.helper.unit')

local cache = {}

g.test_new = function()
    cache = lru_cache.new(1)
    t.assert_equals(type(cache), 'table')
    t.assert_equals(cache:is_empty(), true)
end

g.test_set_ok = function()
    local stale_key = cache:set('x', true)
    t.assert_equals(stale_key, nil)
    t.assert_equals(cache:is_empty(), false)
    t.assert_equals(cache:filled(), 1)
end

g.test_get_ok = function()
    local value = cache:get('x')
    t.assert_equals(value, true)
    t.assert_equals(cache:is_empty(), false)
    t.assert_equals(cache:filled(), 1)
end

g.test_is_full = function()
    t.assert_equals(cache:is_full(), true)
    local stale_key = cache:set('y', 42)
    t.assert_equals(stale_key, 'x')
    t.assert_equals(cache:is_full(), true)
end

g.test_get_not_found = function()
    local value = cache:get('x')
    t.assert_equals(value, nil)
end

g.test_remove_ok = function()
    local ok = cache:remove('y')
    t.assert_equals(ok, true)
    t.assert_equals(cache:get('y'), nil)
    t.assert_equals(cache:is_empty(), true)
end

g.test_remove_not_found = function()
    local ok = cache:remove('y')
    t.assert_equals(ok, false)
end
```

Теперь приступим к тестированию CRUD функций, которые мы создали для роли `storage`. Тестирование данных функций осложняется тем, что они имеют внешнюю зависимость - модуль mysql_handlers. Для решения этой проблемы напишем модуль заглушку, предоставляющий такой же интерфейс как и исходный модуль, а также позволяющий задавать возращаемое значение и контроллировать число вызовов функций.  
Создадим папку `mocks` внутри `tests`. В ней создадим файл `mysql_hanlders_mock.lua`.

```lua
--mysql_handlers_mock.lua
local get_calls_count = 0
local add_calls_count = 0
local update_calls_count = 0
local delete_calls_count = 0

-- Значение, возвращаемое из функций-заглушек
local retvalue = nil

local function set_retvalue(value)
    retvalue = value
end

-- Количество вызовов функций-заглушек
local function calls_count()
    return get_calls_count + add_calls_count + update_calls_count + delete_calls_count
end

local function profile_get(self, id)
    get_calls_count = get_calls_count + 1
    return retvalue
end

local function profile_add(self, profile)
    add_calls_count = add_calls_count + 1
    return retvalue
end

local function profile_update(self, id, new_profile)
    update_calls_count = update_calls_count + 1
    return retvalue
end

local function profile_delete(self, id)
    delete_calls_count = delete_calls_count + 1
    return retvalue
end

local function new(conn_count)
    local instance =  {
        profile_get = profile_get,
        profile_add = profile_add,
        profile_update = profile_update,
        profile_delete = profile_delete,
    }
return instance
end

return {
    new = new,
    set_retvalue = set_retvalue,
    calls_count = calls_count
}
```

Для того, чтобы подменить оригинальный модуль нашей заглушкой внутри теста изменим значение `package.loaded['mysql_handlers']` на модуль-заглушку перед загрузкой модуля `storage`.

```lua
local mock = require('test.mocks.mysql_handlers_mock')
package.loaded['app.mysql_handlers'] = mock
local storage = require('app.roles.storage')
```

Теперь при вызове функций из модуля `storage` вместо функций из модуля `mysql_handlers` будут вызываться функции-заглушки из модуля `mysql_handlers_mock`. Для изменения возвращаемого значения можем воспользоваться `mock.set_retvalue`, а для определения числа вызова функций-заглушек `mock.calls_count()`. 

```lua
-- storage_test.lua

local t = require('luatest')
local g = t.group('unit_storage_utils')
local helper = require('test.helper.unit')

require('test.helper.unit')

local mock = require('test.mocks.mysql_handlers_mock')
package.loaded['app.mysql_handlers'] = mock

local storage = require('app.roles.storage')
local utils = storage.utils

g.test_sample = function()
    t.assert_equals(type(box.cfg), 'table')
end

g.test_profile_get_not_found = function()
    mock.set_retvalue(nil)
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_get(10), nil)
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_get_found_in_base = function()
    local profile = {
        profile_id = 2,
        bucket_id = 1, 
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 100,
        service_info = 'admin'
    }
    local profile_no_bucket = helper.deepcopy(profile)
    profile_no_bucket.bucket_id = nil
    mock.set_retvalue(helper.deepcopy(profile))
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_get(2), profile_no_bucket)
    t.assert_equals(box.space.profile:get(2), box.space.profile:frommap(profile))
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_get_found_in_cache = function ()
    mock.set_retvalue(nil)
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_get(2), {
        profile_id = 2, 
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 100,
        service_info = 'admin'
    })
    t.assert_equals(mock.calls_count(), previous_calls, 'mysql must not be called if key is in cache')
end

g.test_profile_add_ok = function()
    local profile = {
        profile_id = 1,
        bucket_id = 1, 
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 100,
        service_info = 'admin'
    }
    mock.set_retvalue(true)
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_add(helper.deepcopy(profile)), true)
    t.assert_equals(box.space.profile:get(1), box.space.profile:frommap(profile))
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_add_conflict_in_cache = function()
    local profile = {
        profile_id = 1,
        bucket_id = 1, 
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 100,
        service_info = 'admin'
    }
    mock.set_retvalue(false)
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_add(helper.deepcopy(profile)), false)
    t.assert_equals(mock.calls_count(), previous_calls, 'mysql must not be called if key is in cache')
end

g.test_profile_add_conflict_in_base = function()
    local profile = {
        profile_id = 10,
        bucket_id = 1, 
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 100,
        service_info = 'admin'
    }
    mock.set_retvalue(false)
    local previous_calls = mock:calls_count()
    t.assert_equals(utils.profile_add(helper.deepcopy(profile)), false)
    t.assert_equals(mock:calls_count(), previous_calls + 1 , 'mysql myst be called once')
end

g.test_profile_update_exists_in_base = function()
    local profile = {
        profile_id = 10,
        bucket_id = 1, 
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 100,
        service_info = 'admin'
    }
    local new_profile = {
        msgs_count = 100
    }

    mock.set_retvalue(helper.deepcopy(profile))
    local previous_calls = mock.calls_count()
    local profile_no_bucket = helper.deepcopy(profile)
    profile_no_bucket.bucket_id = nil
    t.assert_equals(utils.profile_update(10, new_profile), profile_no_bucket)
    t.assert_equals(box.space.profile:get(10), box.space.profile:frommap(profile))
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_update_exists_in_box = function()
    local profile = {
        profile_id = 10,
        bucket_id = 1,
        first_name = 'Petr',
        second_name = 'Petrov',
        patronymic = 'Ivanovich',
        msgs_count = 322,
        service_info = 'admin'
    }
    local new_profile = {
        msgs_count = 322
    }

    mock.set_retvalue(helper.deepcopy(profile))
    local previous_calls = mock.calls_count()
    local profile_no_bucket = helper.deepcopy(profile)
    profile_no_bucket.bucket_id = nil
    t.assert_equals(utils.profile_update(10, new_profile), profile_no_bucket)
    t.assert_equals(box.space.profile:get(10), box.space.profile:frommap(profile))
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_update_not_found = function()
    mock.set_retvalue(nil)
    local previous_calls = mock:calls_count()
    t.assert_equals(utils.profile_update(12,{msgs_count = 255}), nil)
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_delete_ok = function()
    mock.set_retvalue(true)
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_delete(10), true)
    t.assert_equals(box.space.profile:get(10), nil,  'tuple must be deleted from space')
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.test_profile_delete_not_found = function()
    mock.set_retvalue(false)
    local previous_calls = mock.calls_count()
    t.assert_equals(utils.profile_delete(10), false)
    t.assert_equals(mock.calls_count(), previous_calls + 1, 'mysql must be called once')
end

g.before_all(function()
    -- Выполним инициализацию модуля, чтобы создались экземпляры кэша и заглушки подключения к базе
    storage.init({is_master=true})
end)
```

### Интеграционные тесты

Для проверки правильности взаимодействий различных частей приложения(Cartridge, MySQL) напишем интеграционные тесты. Во время тестирования запустим приложение и проверим работоспособность с помощью http запросов.

Настроить конфигурацию тестируемого приложения можно в файле `test/helper/integration.lua`.

```lua
-- integration.lua
...
helper.cluster = cartridge_helpers.Cluster:new({
    server_command = shared.server_command,
    datadir = shared.datadir,
    use_vshard = true,
    -- Репликасеты, используемые в приложении
    replicasets = {
        {
            alias = 'api',
            uuid = cartridge_helpers.uuid('a'),
            roles = {'api'},
            servers = {{ instance_uuid = cartridge_helpers.uuid('a', 1) }},
        },
        {
            alias = 'storage',
            uuid = cartridge_helpers.uuid('b'),
            roles = {'storage'},
            servers = {
                { instance_uuid = cartridge_helpers.uuid('b', 1)},
                { instance_uuid = cartridge_helpers.uuid('b', 2)},
            }
        },
    },
})
```

Для удобства дальнейшего тестирования здесь же опишем функцию, выполняющую http запрос к приложению и проверяющую правильность ответа.

```lua
helper.assert_http_json_request = function (method, path, body, expected)
    checks('string', 'string', '?table', 'table')
    local response = helper.cluster.main_server:http_request(method, path, {
        json = body,
        headers = {["content-type"]="application/json; charset=utf-8"},
        raise = false
    })
    
    if expected.body then
        t.assert_equals(response.json, expected.body)
    end

    t.assert_equals(response.status, expected.status)

    return response
end
```

В файле `test/integration/api_test.lua` опишем тесты

```lua
--api_test.lua

local t = require('luatest')
local g = t.group('integration_api')

local helper = require('test.helper.integration')
local cluster = helper.cluster

local mysql = require('mysql')

local profile_1 = {
    profile_id = 1, 
    first_name = 'Petr',
    second_name = 'Petrov',
    patronymic = 'Ivanovich',
    msgs_count = 110,
    service_info = 'admin'
}

g.test_sample = function()
    local server = cluster.main_server
    local response = server:http_request('post', '/admin/api', {json = {query = '{}'}})
    t.assert_equals(response.json, {data = {}})
    t.assert_equals(server.net_box:eval('return box.cfg.memtx_dir'), server.workdir)
end

g.test_on_get_not_found = function()
    helper.assert_http_json_request('get', '/profile/1', nil, {body = {info = "Profile not found"}, status = 404})
end

g.test_on_post_ok = function ()
    helper.assert_http_json_request('post', '/profile', profile_1, {status=201})
end

g.test_on_post_conflict = function()
    helper.assert_http_json_request('post', '/profile', profile_1, {body = {info = "Profile already exist"}, status=409})
end

g.test_on_get_ok = function ()
    helper.assert_http_json_request('get', '/profile/1', nil, {body = profile_1, status = 200})
end

g.test_on_put_not_found = function()
    helper.assert_http_json_request('put', '/profile/2', {msgs_count = 115}, {body = {info = "Profile not found"}, status = 404})
end

g.test_on_put_ok = function()
    local changed_profile = profile_1
    changed_profile.msgs_count = 115
    helper.assert_http_json_request('put', '/profile/1', {msgs_count = 115}, {body = changed_profile, status = 200})
end

g.test_on_delete_not_found = function ()
    helper.assert_http_json_request('delete', '/profile/2', nil, {body = {info = "Profile not found"}, status = 404})
end

g.test_on_delete_ok = function()
    helper.assert_http_json_request('delete', '/profile/1', nil, {body = {info = "Deleted"}, status = 200})
end

g.before_all = function ()
    -- Подготовим базу перед тестированием
    local connection = mysql.connect({
        host='127.0.0.1', 
        user='tarantool-user', 
        password='password', 
        db='profile_storage',
    })
    connection:execute('DELETE FROM user_profile')
    connection:close()
end
```

Запустить тесты можно с помощью команды `.rocks/bin/luatest` в корневой директории приложения.

## Запуск проекта
Можем запускать кластер!
```bash
profiles-storage $ tarantoolctl rocks make
profiles-storage $ cartridge start
```

>> При запуске возможна ошибка прав доступа, для ее исправления выполните команду `chmod u+x init.lua` в терминале

Откроем в браузере веб-интерфейс и сделаем следующее:
1. Создадим в одном экземпляре роль `api`  
![](report_images/api-role.png)
2. Cоздадим на другом экземпляре роль `storage`  
![](report_images/storage-role.png)

Должны создаться 2 репликасета по одному экземпляру Tarantool в каждом. 
![](report_images/two-replicasets.png)

Теперь у нас есть 2 репликасета с двумя ролями, но vshard еще не запущен. Нажмем кнопку Bootstrap vshard на закладке Cluster в веб-интерфейсе.

Запустим кластер, нажав кнопку **Bootstrap vshard** в правом верхнем углу веб-интерфейса.

## Проверим работу

Откроем новую консоль и добавим профиль через `curl`:
```bash
you@yourmachine$ curl -X POST -v -H "Content-Type: application/json" -d '{
"profile_id": 1,
"first_name": "Ivan",
"second_name": "Ivnov",
"patronymic": "Ivanovich",
"msgs_count": 100,
"service_info": "admin"
}' http://localhost:8081/profile
```

В ответе мы должны увидеть примерно следующее:
```bash
*   Trying 127.0.0.1:8081...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8081 (#0)
> POST /profile HTTP/1.1
> Host: localhost:8081
> User-Agent: curl/7.65.3
> Accept: */*
> Content-Type: application/json
> Content-Length: 136
> 
* upload completely sent off: 136 out of 136 bytes
* Mark bundle as not supporting multiuse
< HTTP/1.1 201 Created
< Content-length: 31
< Server: Tarantool http (tarantool v2.1.3-6-g91e2a9638)
< Content-type: application/json; charset=utf-8
< Connection: keep-alive
< 
* Connection #0 to host localhost left intact
{"info":"Successfully created"}
```

Проверим, что данные корректно сохранились в бд, сделаем GET запрос

```bash
you@yourmachine$ curl -X GET -v http://localhost:8081/profile/1
```
```bash
*   Trying 127.0.0.1:8081...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8081 (#0)
> GET /profile/1 HTTP/1.1
> Host: localhost:8081
> User-Agent: curl/7.65.3
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 Ok
< Content-length: 42
< Server: Tarantool http (tarantool v2.1.3-6-g91e2a9638)
< Content-type: application/json; charset=utf-8
< Connection: keep-alive
< 
* Connection #0 to host localhost left intact
{"second_name":"Ivnov","msgs_count":100,"patronymic":"Ivanovich","service_info":"admin","first_name":"Ivan","profile_id":1}
```

Исправим опечатку в фамилии пользователя с помощью PUT запроса

```bash
you@yourmachine$ curl -X PUT -v -H "Content-Type: application/json" -d '{
"second_name": "Ivanov"
}' http://localhost:8081/profile/1
```

```bash
*   Trying 127.0.0.1:8081...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8081 (#0)
> PUT /profile/1 HTTP/1.1
> Host: localhost:8081
> User-Agent: curl/7.65.3
> Accept: */*
> Content-Type: application/json
> Content-Length: 27
> 
* upload completely sent off: 27 out of 27 bytes
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 Ok
< Content-length: 124
< Server: Tarantool http (tarantool v2.1.3-6-g91e2a9638)
< Content-type: application/json; charset=utf-8
< Connection: keep-alive
< 
* Connection #0 to host localhost left intact
{"second_name":"Ivanov","msgs_count":100,"patronymic":"Ivanovich","service_info":"admin","first_name":"Ivan","profile_id":1}
```

Теперь удалим этого пользователя с помощью DELETE запроса

```bash
curl -X DELETE -v http://localhost:8081/profile/1
```

```bash
*   Trying 127.0.0.1:8081...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8081 (#0)
> DELETE /profile/1 HTTP/1.1
> Host: localhost:8081
> User-Agent: curl/7.65.3
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 Ok
< Content-length: 11
< Server: Tarantool http (tarantool v2.1.3-6-g91e2a9638)
< Content-type: application/json; charset=utf-8
< Connection: keep-alive
< 
* Connection #0 to host localhost left intact
{"info":"Deleted"}
```

Убедимся, что пользователь был действительно удален

```bash
you@yourmachine$ curl -X GET -v http://localhost:8081/profile/1
```

```bash
*   Trying 127.0.0.1:8081...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8081 (#0)
> GET /profile/1 HTTP/1.1
> Host: localhost:8081
> User-Agent: curl/7.65.3
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 404 Not found
< Content-length: 28
< Server: Tarantool http (tarantool v2.1.3-6-g91e2a9638)
< Content-type: application/json; charset=utf-8
< Connection: keep-alive
< 
* Connection #0 to host localhost left intact
{"info":"Profile not found"}
```
