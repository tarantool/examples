# Кеш

## Задачи

1. Обычный кеш (memcache)
2. Кеш с базой данных MySQL
3. Кеш с базой данных Vinyl

## 1. Роль Router
Будем реализовывать логику хранилища аккаунтов. Это хранилище должно быть способно обрабатывать запросы на создание и удаление аккаунтов, чтение и обновление информации. 

Первым делом необходимо создать роль Router, которая будет принимать и обрабатывать запросы, обращаясь в кеш. 

Для корректной работы подключим необходимые библиотеки

```lua
local vshard = require('vshard')
local cartridge = require('cartridge')
local errors = require('errors')

local err_vshard_router = errors.new_class("Vshard routing error")
local err_httpd = errors.new_class("httpd error")
```

1) Первой функцией, которую нужно реализовать, будет функция создания аккаунта. Назовем ее `http_account_add`. 

```lua
local function http_account_add(req)
    local time_stamp = os.clock() --время начала работы функции
    local account = req:json() --преобразование данных из json в таблицу
	local bucket_id = vshard.router.bucket_id(account.login)
    account.bucket_id = bucket_id
    
    --вызов функции создания аккаунта хранилища
    local success, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'account_add',
        {account}
    )
    
    --внутренняя ошибка
    if error then
        local resp = req:render({json = {
            info = "Internal error",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 500
        return resp
    end
    
    --аккаунт уже существует
    if success == false then
    	local resp = req:render({json = {
            info = "Account with such login exists",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 409
        return resp
    end
    
    local resp = req:render({json = { info = "Account successfully created", 	
                			time = os.clock() - time_stamp}})
    resp.status = 201
    return resp
end
```

Данная функция обращается к кешу и, если аккаунт создан, возвращает сообщение об успехе операции. 

2) С `http_account_delete` удаляет аккаунт из хранилища.

```lua
local function http_account_delete(req)
    local time_stamp = os.clock() --время начала работы функции
    local login = req:stash('login')
	local bucket_id = vshard.router.bucket_id(login)
	
    --вызов функции удаления аккаунта хранилища
	local success, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'read',
        'account_delete',
        {login}
    )
    
	--внутренняя ошибка
    if error then
        local resp = req:render({json = {
            info = "Internal error",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 500
        return resp
    end
    
    --аккаунт не найден
    if success == nil then
        local resp = req:render({json = {
            info = "Account not found",
            time = os.clock() - time_stamp,
            error = error,
        }})
        resp.status = 404
        return resp
    end

    --сессия не активна
    if success == false then
        local resp = req:render({json = {
            info = "Sign in first. Session is down",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 401
        return resp
    end

    local resp = req:render({json = {info = "Account deleted", 														time = os.clock() - time_stamp}})
    resp.status = 200
    return resp
end
```



3)  `http_account_get` позволяет получить значение заданного поля аккаунта.

```lua
local function http_account_get(req)
    local time_stamp = os.clock()
	local login = req:stash('login')
	local field = req:stash('field')
	local bucket_id = vshard.router.bucket_id(login)

    --вызов функции get хранилища
	local account_data, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'read',
        'account_get',
        {login, field}
    )
	
    if error then
        local resp = req:render({json = {
            info = "Internal error",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 500
        return resp
    end

    --аккаунт не найден
    if account_data == nil then
        local resp = req:render({json = {
            info = "Account not found",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 404
        return resp
    end

    --сессия не активна 
    if account_data == false then
        local resp = req:render({json = {
            info = "Sign in first. Session is down",
            time = os.clock() - time_stamp,
        }})
        resp.status = 401
        return resp
    end

    --неправильное поле
    if account_data == -1 then
        local resp = req:render({json = {
            info = "Invalid field",
            time = os.clock() - time_stamp,
        }})
        resp.status = 400
        return resp
    end

    local resp = req:render({json = {info = account_data, 															time = os.clock() - time_stamp}})
    resp.status = 200
    return resp
end
```



4) `http_account_update` позволяет изменить значение заданного поля аккаунта.

```lua
local function http_account_update(req)
    local time_stamp = os.clock()
	local login = req:stash('login')
	local field = req:stash('field')
	local bucket_id = vshard.router.bucket_id(login)

	local value = req:json().value

    --вызов функции update хранилища
	local success, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'account_update',
        {login, field, value}
    )

    if error then
        local resp = req:render({json = {
            info = "Internal error",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 500
        return resp
    end

    --аккаунт не найден
    if success == nil then
        local resp = req:render({json = {
            info = "Account not found",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 404
        return resp
    end

    --сессия не активна
    if success == false then
        local resp = req:render({json = {
            info = "Sign in first. Session is down",
            time = os.clock() - time_stamp,
        }})
        resp.status = 401
        return resp
    end

    --неправильное поле
    if success == -1 then
        local resp = req:render({json = {
            info = "Invalid field",
            time = os.clock() - time_stamp,
        }})
        resp.status = 400
        return resp
    end

    local resp = req:render({json = {info = "Field updated", 
                			time = os.clock() - time_stamp}})
    resp.status = 200
    return resp
end
```



Чтобы сделать пример более интересным, можно сымитировать проверку пароля. Для этого добавим следующие функции:

`http_account_sign_in`: 

``` lua
local function http_account_sign_in(req)
	local time_stamp = os.clock()
	local login = req:stash('login')
	local password = req:json().password
	local bucket_id = vshard.router.bucket_id(login)

	local success, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'account_sign_in',
        {login, password}
    )

	if error then
        local resp = req:render({json = {
            info = "Internal error",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 500
        return resp
    end

    --аккаунт не найден
    if success == nil then
    	local resp = req:render({json = {
            info = "Account not found",
            time = os.clock() - time_stamp,
            error = error
       	 }})
        resp.status = 404
        return resp
    end

    --неправильный пароль
    if success == false then
    	local resp = req:render({json = {
            info = "Wrong password",
            time = os.clock() - time_stamp,
            error = error,
       	 }})
        resp.status = 401
        return resp
    end

    local resp = req:render({json = { info = "Accepted", time = os.clock() - time_stamp}})
    resp.status = 202
    return resp

end
```

`http_sign_out`:

```lua
local function http_account_sign_out(req)
    local time_stamp = os.clock()
	local login = req:stash('login')
	local bucket_id = vshard.router.bucket_id(login)

	local success, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'account_sign_out',
        {login}
    )

    --аккаунт не найден
    if success == nil then
    	local resp = req:render({json = {
            info = "Account not found",
            time = os.clock() - time_stamp,
            error = error
       	 }})
        resp.status = 404
        return resp
    end

	if error then
        local resp = req:render({json = {
            info = "Internal error",
            time = os.clock() - time_stamp,
            error = error
        }})
        resp.status = 500
        return resp
    end

    local resp = req:render({json = { info = "Success", time = os.clock() - time_stamp}})
    resp.status = 200
    return resp

end
```



Назначим функции соответствующим запросам.

```lua
local function init(opts)
    rawset(_G, 'vshard', vshard)

    if opts.is_master then
        box.schema.user.grant('guest',
            'read,write,execute',
            'universe',
            nil, { if_not_exists = true }
        )
    end

    local httpd = cartridge.service_get('httpd')

    if not httpd then
        return nil, err_httpd:new("not found")
    end

    -- assigning handler functions
    httpd:route(
        { path = '/storage/:login/sign_in', method = 'PUT', public = true },
        http_account_sign_in
    )
	httpd:route(
        { path = '/storage/:login/sign_out', method = 'PUT', public = true },
        http_account_sign_out
    )
	httpd:route(
        { path = '/storage/:login/update/:field', method = 'PUT', public = true },
        http_account_update
    )
    httpd:route(
        { path = '/storage/create', method = 'POST', public = true },
        http_account_add
    )
    httpd:route(
        { path = '/storage/:login/:field', method = 'GET', public = true },
        http_account_get
    )
    httpd:route(
        { path = '/storage/:login', method = 'DELETE', public = true },
        http_account_delete
    )

    return true
end
```



В конце необходимо вернуть данные о роли.

```lua
return {
    role_name = 'api',
    init = init,
    dependencies = {'cartridge.roles.vshard-router'},
}
```





## 2. Обычный кеш

Сперва необходимо подключить все необходимые модули и сопоставить имя поля с номером (для удобства).

```lua
local checks = require('checks') -- для проверки аргументов функций
local lru = require('lru') -- кеш lru, реализованный с помощью двухсвязного списка
local log = require('log')

local field_no = {
    name = 5,
    email = 6,
    data = 8,
}
```



`verify_session`  используется для проверки существования и доступности аккаунта.

```lua
local function verify_session(account)
    if account == nil then --аккаунт не найден
        return false, nil
    end

    if account[3] == 1 then --если сессия активна, вернуть true
        return true
    end
	--сессия не активна
    return false, false
end
```



1)  Сначала необходимо инициализировать хранилище кеша. Сделать это можно с помощью `box.schema.space.create`.

```lua
local function init_spaces()
    local account = box.schema.space.create(
        'account',
        {
            format = {
                {'login', 'string'},
                {'password', 'string'},
                {'session', 'number'},
                {'bucket_id', 'unsigned'},
                {'name', 'string'},
                {'email', 'string'},
                {'last_action', 'unsigned'},
                {'data', 'string'}
            },
            if_not_exists = true,
            engine = 'memtx', -- движок для хранения данных в RAM
        }
    )

    account:create_index('login', {
        parts = {'login'},
        if_not_exists = true,
    })

    account:create_index('bucket_id', {
        parts = {'bucket_id'},
        unique = false,
        if_not_exists = true,
    })
end
```

2)  `account_add` создает новый аккаунт в кеше.

```lua
local function account_add(account)
    --проверка существования
    local tmp = box.space.account:get(account.login) --
    if tmp ~= nil then
        return false
    end

    --добавление нового аккаунта
    box.space.account:insert({
        account.login,
        account.password,
        1,
        account.bucket_id,
        account.name,
        account.email,
        os.time(),
        account.data
    })

    return true
end
```

3)  `account_delete` удаляет аккаунт из кеша.

```lua
local function account_delete(login)
    checks('string')

    --проверка существования и достпуности
    local account = box.space.account:get(login) 
    local valid, err = verify_session(account)
    if not valid then
        return err
    end

    --удаление аккаунта
    local account = box.space.account:delete(login)

    return true
end
```

4)  `account_get` возвращает значения определенного поля аккаунта.

```lua
local function account_get(login, field)
    checks('string', 'string')

    --проверка корректности поля
    local field_n = field_no[field] 
    if field_n == nil then 
        return -1
    end

    --проверка существования и достпуности
    local account = box.space.account:get(login) 
    local valid, err = verify_session(account)
    if not valid then
        return err
    end

    --обновление времени последнего обращения к аккаунту
    box.space.account:update({login}, {
        {'=', 7, os.time()}
    })

    return account[field_n]
end
```



5) Функция `account_update` позволяет изменять значения определенного поля аккаунта.

```lua
local function account_update(login, field, value)

    --проверка корректности поля
    local field_n = field_no[field]
    if field_n == nil then 
        return -1
    end

    --проверка существования и доступности
    local account = box.space.account:get(login)
    local valid, err = verify_session(account)
    if not valid then
        return err
    end

    --обновление заданного поля и времени последнего обращения
    box.space.account:update({ login }, {
        { '=', field_n, value},
        { '=', 7, os.time()}
    })

    return true
end
```



Для проверки паролей добавим следующие функции:

`account_sign_in`:

```lua
local function account_sign_in(login, password)
    checks('string', 'string')

   	--проверка существования
    local account = box.space.account:get(login) 
    if account == nil then 
        return nil
    end

    --проверка корректности пароля
    if password ~= account[2] then 
        return false
    end

    --создание сессии и обновление времени последнего обращения 
    box.space.account:update({ login } , {
        {'=', 3, 1},
        {'=', 7, os.time()}
    })

    return true
end
```

`account_sign_out`:

```lua
local function account_sign_out(login)
    checks('string')

    --проверка существования и доступности 
    local account = box.space.account:get(login) 
    local valid, err = verify_session(account)
    if not valid then
        return err
    end

    --закрытие сессии и обновление времени последнего обращения
    box.space.account:update({ login } , {
        {'=', 3, -1},
        {'=', 7, os.time()} --update last action timestamp
    })

    return true
end
```



Теперь можно инициализировать хранилище и объявить функции.

```lua
local function init(opts)
    if opts.is_master then

        init_spaces()

        box.schema.func.create('account_add', {if_not_exists = true})
        box.schema.func.create('account_sign_in', {if_not_exists = true})
        box.schema.func.create('account_sign_out', {if_not_exists = true})
        box.schema.func.create('account_delete', {if_not_exists = true})
        box.schema.func.create('account_update', {if_not_exists = true})
        box.schema.func.create('account_get', {if_not_exists = true})

        box.schema.role.grant('public', 'execute', 'function', 'account_add', 											{if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'account_sign_in', 										{if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'account_sign_out', 										{if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'account_delete', 										{if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'account_update', 										{if_not_exists = true})
        box.schema.role.grant('public', 'execute', 'function', 'account_get', 											{if_not_exists = true})

    end

    rawset(_G, 'account_add', account_add)
    rawset(_G, 'account_sign_in', account_sign_in)
    rawset(_G, 'account_sign_out', account_sign_out)
    rawset(_G, 'account_get', account_get)
    rawset(_G, 'account_delete', account_delete)
    rawset(_G, 'account_update', account_update)

    return true
end
```

В конце необходимо вернуть данные о роли.

```lua
return {
    role_name = 'simple_cache',
    init = init,
    dependencies = {
        'cartridge.roles.vshard-storage',
    },
    utils = {
        verify_session = verify_session,
        account_add = account_add, 
        account_update = account_update,
        account_delete = account_delete, 
        account_get = account_get,
        account_sign_in = account_sign_in, 
        account_sign_out = account_sign_out,
    }
}
```



## 3. Кеш с базой данных MySQL

Эффективным подходом при работе с базами данных является разделение данных на горячие и холодные. Горячие данные хранятся в кеше, что обеспечивает высокую скорость доступа, а холодные находятся в базе данных на жестоком диске. Реализуем подобную схему с помощью MySQL. Модифицируем для этого обычный кеш.

Но сперва необходимо настроить хранилище в MySQL. Сделать это можно с помощью следующих команд:

```bash
mysql> CREATE DATABASE tarantool;
mysql> USE tarantool;
mysql> CREATE TABLE account (login VARCHAR(30), password VARCHAR(30), session TINYINT, 						bucket_id INT, name VARCHAR(30), email VARCHAR(30), data VARCHAR(30));

```



Добавим две глобальные переменные. `lru_cache` реализует работу lru кеша. При превышении кол-ва аккаунтов в кеше некоторого значения `cache_size` из него удаляется объект, к которому дольше всего не обращались.  `conn` осуществляет взаимодействие с MySQL.

Добавим в  `init_spaces` следующие строки:

```lua
--подключение к базе данных MySQL
conn = mysql.connect({
        host = '127.0.0.1', 
        user = 'root', 
        password = '1234', 
        db = 'tarantool'
    })

--создание и заполнение lru кеша
lru_cache = lru.new(cache_size)
for k, account in box.space.account:pairs() do --прогрев кеша
    update_cache(account[1])
end
```



При отсутствии данных в кеше их необходимо загрузить из MySQL. 

```lua
local function fetch(login)
    checks('string') 

    --запрос аккаунта с заданным логином
    local account = conn:execute(string.format(
            "SELECT * FROM account WHERE login = \'%s\'", login))

    --если он не существует, то вернуть nil
    if (#account[1] == 0) then 
        return nil
    end

    --добавить данный аккаунт в кеш
    account = account[1][1]
    local time = os.time()
    local tmp = {
        account.login,
        account.password,
        account.session,
        account.bucket_id,
        account.name,
        account.email,
        time,
        account.data
    }
	box.space.account:insert(tmp)

    log.info(string.format("\'%s\' uploaded from mysql", tmp[1]))

    return tmp
end
```

Теперь в функциях `account_add`, `account_update`, `account_get` и т.д. нужно изменить формат запроса аккаунта. Если его нет в кеше, то нужно проверить холодное хранилище прежде, чем сообщать об отсутствии.

```lua
local account = box.space.account:get(login) --запрос аккаунта в кеше
if account == nil then
	account = fetch(login) --если нет в кеше, то запрос в MySQL
end

--проверка существования и доступности
local valid, err = verify_session(account)
if not valid then
	return err
end
```

Таким образом реализуется загрузка данных из холодного хранилища. Но если к данным долго не обращаются, то их следует удалить из горячего хранилища. 

```lua
local function update_cache(login)
    checks('string')

    --обновление положения аккаунта login в очереди кеша
    local result, err = lru_cache:touch(login)

    if err ~= nil then
        return nil, err
    end

    --если кеш не переполнен, то ничего удалять не нужно
    if result == true then 
        return true
    end
    
    --иначе удаление невостребованного элемента
    log.info(string.format("Removing \'%s\' from cache", result))
    box.space.account:delete(result)

    return true
end
```

`update_cache` следует вызывать при каждом взаимодействии с данными. 

При обновлении данных в кеше их можно сразу же обновлять и в холодном хранилище. Кроме того, изменения можно накапливать и обновлять хранилище разом. Порой подобный подход более эффективен. Для этого создадим массив `write_queue`. При изменении аккаунта он помещается в `write_queue` с помощью функции  `set_to_update`.

```lua
local function set_to_update(login)
    checks('string')

    if write_queue[login] == nil then
        write_queue[login] = true
    end

    return true
end

```

 Накопленные изменения записываются в холодное хранилище.

```lua
local function write_behind()

    for login, _ in pairs(write_queue) do

        local account = box.space.account:get(login)
        if (account ~= nil) then
            
            --обновление аккаунта в базе данных MySQL
            conn:execute(string.format("REPLACE INTO account value (\'%s\', \'%s\', 					\'%d\', \'%d\', \'%s\', \'%s\', \'%s\')", 
                account[1], 
                account[2], 
                account[3], 
                account[4], 
                account[5], 
                account[6], 
                account[8]
            ))

            log.info(string.format("\'%s\' updated in mysql", account[1]))
            
        end
    end

    write_queue = {}
    return true
end
```



В функции `account_delete` нужно также удалить аккаунт из холодного хранилища.

```     lua
conn:execute(string.format("DELETE FROM account WHERE login = \'%s\'", login ))
```



## 4. Кеш с базой данных Vinyl

Хорошей альтернативой MySQL является Vinyl, встроенный в Tarantool. Первым делом вместо подключения к MySQL в `init_spaces` настроим новое хранилище:

```lua
local account_vinyl = box.schema.space.create(
    'account_vinyl',
    {
        format = {
        {'login', 'string'},
        {'password', 'string'},
        {'session', 'number'},
        {'bucket_id', 'unsigned'},
        {'name', 'string'},
        {'email', 'string'},
        {'data', 'string'}
    },
    if_not_exists = true,
    engine = 'vinyl'
    }
)

account_vinyl:create_index('login', {
    parts = {'login'},
    if_not_exists = true,
})

account_vinyl:create_index('bucket_id', {
    parts = {'bucket_id'},
    unique = false,
    if_not_exists = true,
})
```

Вся логика работы с аккаунтами остается та же, необходимо лишь слегка изменить вспомогательные функции.

`fetch`:

```lua
local function fetch(login) 
    checks('string')
	
    --проверка существования
    local account = box.space.account_vinyl:get(login) 
    if account == nil then 
        return nil
    end
	
    --добавление аккаунта в кеш
    local time = os.time()
    local tmp = {
        account.login,
        account.password,
        account.session,
        account.bucket_id,
        account.name,
        account.email,
        time,
        account.data
    }
	box.space.account:insert(tmp)   

    log.info(string.format("\'%s\' uploaded from vinyl", tmp[1]))
    return tmp
end
```

`write_behind`:

```lua
local function write_behind()

    for login, _ in pairs(write_queue) do

        local account = box.space.account:get(login)
        if (account ~= nil) then
            
            --обновление аккаунта в vinyl
            box.space.account_vinyl:upsert({
                account[1], 
                account[2], 
                account[3], 
                account[4], 
                account[5], 
                account[6], 
                account[8],
            }, {
                {'=', 1, account[1]},
                {'=', 2, account[2]},
                {'=', 3, account[3]},
                {'=', 4, account[4]},
                {'=', 5, account[5]},
                {'=', 6, account[6]},
                {'=', 7, account[8]}
            })

            log.info(string.format("\'%s\' updated in vinyl", account[1]))
        end
    end

    write_queue = {}
    return true
end
```

А в `account_delete` добавятся следующие строки:

```lua
if peek_vinyl(login) then
	box.space.account_vinyl:delete(login)
end
```

где `peek_vinyl` - это функция, которая проверяет наличие аккаунта в хранилище.

```lua
local function peek_vinyl(login) 
    checks('string')

    local account = box.space.account_vinyl:get(login)
    if account == nil then 
        return false
    end

    return true
end
```

