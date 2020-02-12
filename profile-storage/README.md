# Хранилище профилей пользователей на Tarantool Cartridge

## Содержание

* [Что будем делать](#что-будем-делать)
* [Настройка окружения](#настройка-окружения)
* [Модуль авторизации](#модуль-авторизации)
* [Немного о ролях](#немного-о-ролях)
* [Роль хранилища (`storage`)](#роль-хранилища-storage)
* [Роль http-сервера (`api`)](#роль-http-сервера-api)
* [Добавление зависимостей](#добавление-зависимостей)
* [Тестирование](#тестирование)
* [Запуск приложения](#запуск-приложения)
* [Проверка работоспособности](#проверка-работоспособности)

## Что будем делать

В этом примере мы создадим хранилище профилей пользователей с поддержкой команд
POST, PUT, GET, DELETE для добавления, изменения, чтения и удаления профиля.

Мы также добавим проверку пароля для пользователей, чтобы только сам пользователь
мог выполнять операции над своим профилем.

Для разработки будем пользоваться фреймворком Tarantool Cartridge.

## Настройка окружения

Для работы с Tarantool Cartridge необходимо установить `cartridge-cli`
(версию 1.3.1):

```bash
tarantoolctl rocks install cartridge-cli 1.3.1
```

Исполняемый файл будет сохранен в `.rocks/bin/cartridge`.
Подробнее про установку `cartridge-cli` можно прочитать
[здесь](https://github.com/tarantool/cartridge-cli#installation).

Теперь создадим наше приложение. Назовем его `profiles-storage`:

```bash
you@yourmachine $ .rocks/bin/cartridge create --name profiles-storage .
```

## Модуль авторизации

Для безопасного хранения паролей в зашифрованном виде реализуем модуль `auth`
с функциями создания и проверки паролей.

Расположим этот модуль в директории `app`:

```bash
profiles-storage $ touch app/auth.lua
```

Далее:

1. Подключим необходимые модули:

   ```lua
   -- Модуль проверки аргументов в функции
   local checks = require('checks')
   -- Модуль с криптографическими функциями
   local digest = require('digest')
   ```

2. Реализуем несколько функций. Функция генерации соли:

   ```lua
   local SALT_LENGTH = 16

   local function generate_salt(length)
       return digest.base64_encode(
           digest.urandom(length - bit.rshift(length, 2)),
           {nopad=true, nowrap=true}
       ):sub(1, length)
   end
   ```

3. Функция шифрования пароля с помощью соли:

   ```lua
   local function password_digest(password, salt)
       checks('string', 'string')
       return digest.pbkdf2(password, salt)
   end
   ```

4. Функция создания пароля:

   ```lua
   local function create_password(password)
       checks('string')

       local salt = generate_salt(SALT_LENGTH)

       local shadow = password_digest(password, salt)

       return {
           shadow = shadow,
           salt = salt,
       }
   end
   ```

5. Функция проверки пароля:

   ```lua
   local function check_password(profile, password)
       return profile.shadow == password_digest(password, profile.salt)
   end
   ```

6. Экспортируем нужные функции:

   ```lua
   return {
       create_password = create_password,
       check_password = check_password
   }
   ```

## Немного о ролях

Наше приложение-хранилище должно обрабатывать запросы на создание и удаление
профилей, чтение и обновление информации.

Разобьем наше приложение на 2 роли:

1. Роль `storage` реализует хранение и изменение информации о пользователях
   и счетах.
2. Роль `api` реализует RESTful http-сервер.

Кластерная роль – это Lua-модуль, который реализует некоторую функцию и логику.
С помощью Tarantool Cartridge мы можем назначать роли на инстансы Tarantool
в кластере. Подробнее об этом можно прочитать
(тут)[https://www.tarantool.io/ru/doc/2.2/book/cartridge/cartridge_dev/#cluster-roles].

Чтобы реализовать роль, которая будет работать на кластере, то &mdash; помимо
описания бизнес-логики этой роли &mdash; нам необходимо написать несколько функций
обратного вызова, через которые кластер и будет управлять жизненным циклом нашей
роли.

Список этих функций невелик, и почти все из них уже реализованы заглушками при
создании проекта из шаблона. Вот что мы найдем в `app/roles/custom.lua`:

* `init(opts)` &mdash; создание роли и ее инициализация;
* `stop()` &mdash; завершение работы роли;
* `validate_config(conf_new, conf_old)` &mdash; функция валидирования новой
  конфигурации нашей роли;
* `apply_config(conf, opts)` &mdash; применение новой конфигурации.

Как мы уже говорили, сам файл роли &mdash; это просто Lua-модуль,
но в конце него должен быть реализован экспорт необходимых функций и переменных:

```lua
return {
    role_name = 'custom_role',
    init = init,
    stop = stop,
    validate_config = validate_config,
    apply_config = apply_config,
    dependencies = {},
}
```

## Роль хранилища (`storage`)

Первым делом создадим роль, которая инициализирует хранилище и реализует функции
доступа к данным.

Все роли нашего приложения лежат в директории `app/roles`. Для нашей роли
создадим здесь файл `storage.lua`.

```bash
profiles-storage $ touch app/roles/storage.lua
```

Для корректной работы подключим необходимые модули:

```lua
-- модуль проверки аргументов в функциях
local checks = require('checks')
local errors = require('errors')
-- класс ошибок доступа к хранилищу профилей
local err_storage = errors.new_class("Storage error")
-- написанный нами ранее модуль с функциями создания и проверки пароля
local auth = require('app.auth')
```

Идем дальше. Добавим вспомогательные функции:

```lua
-- Функция, преобразующая кортеж в таблицу согласно схеме хранения
local function tuple_to_table(format, tuple)
    local map = {}
    for i, v in ipairs(format) do
        map[v.name] = tuple[i]
    end
    return map
end

-- Функция, заполняющая недостающие поля таблицы minor из таблицы major
local function complete_table(major, minor)
    for k, v in pairs(major) do
        if minor[k] == nil then
            minor[k] = v
        end
    end
end
```

Профили в нашем хранилище будут содержать следующую информацию:

* ФИО
* количество отправленных писем
* сервисную информацию (флаги, зашифрованные пароли, соль)

Зная формат данных, добавим инициализацию необходимого пространства в хранилище:

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
                {'sur_name', 'string'},
                {'patronymic', 'string'},
                {'shadow','string'},
                {'salt', 'string'},
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

Итак, наша основная логика:

1. Функция добавления нового профиля:

   ```lua
   local function profile_add(profile)
       checks('table')

       -- Проверяем существование пользователя с таким id
       local exist = box.space.profile:get(profile.profile_id)
       if exist ~= nil then
           return {ok = false, error = err_storage:new("Profile already exist")}
       end

       local password_data = auth.create_password(profile.password)

       profile.shadow = password_data.shadow
       profile.salt = password_data.salt
       profile.password = nil
       box.space.profile:insert(box.space.profile:frommap(profile))

       return {ok = true, error = nil}
   end
   ```

2. Функция обновления профиля:

   ```lua
   local function profile_update(id, password, changes)
       checks('number', 'string', 'table')

       local exists = box.space.profile:get(id)

       if exists == nil then
           return {profile = nil, error = err_storage:new("Profile not found")}
       end

       exists = tuple_to_table(box.space.profile:format(), exists)
       if not auth.check_password(exists, password) then
           return {profile = nil, error = err_storage:new("Unauthorized")}
       end

       complete_table(exists, changes)
       if changes.password ~= nil then
           local password_data = auth.create_password(changes.password)
           changes.shadow = password_data.shadow
           changes.salt = password_data.salt
           changes.password = nil
       end
       box.space.profile:replace(box.space.profile:frommap(changes))

       changes.bucket_id = nil
       changes.salt = nil
       changes.shadow = nil
       return {profile = changes, error = nil}
   end
   ```

3. Функция получения информации о профиле:

   ```lua
   local function profile_get(id, password)
       checks('number', 'string')

       local profile = box.space.profile:get(id)
       if profile == nil then
           return {profile = nil, error = err_storage:new("Profile not found")}
       end

       profile = tuple_to_table(box.space.profile:format(), profile)
       if not auth.check_password(profile, password) then
           return {profile = nil, error = err_storage:new("Unauthorized")}
       end

       profile.bucket_id = nil
       profile.shadow = nil
       profile.salt = nil
       return {profile = profile, error = nil}
   end
   ```

4. Функция удаления профиля:

   ```lua
   local function profile_delete(id, password)
       checks('number', 'string')

       local exists = box.space.profile:get(id)
       if exists == nil then
           return {ok = false, error = err_storage:new("Profile not found")}
       end
       exists = tuple_to_table(box.space.profile:format(), exists)
       if not auth.check_password(exists, password) then
           return {ok = false, error = err_storage:new("Unauthorized")}
       end

       box.space.profile:delete(id)
       return {ok = true, error = nil}
   end
   ```

5. Функция инициализации роли:

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

       rawset(_G, 'profile_add', profile_add)
       rawset(_G, 'profile_get', profile_get)
       rawset(_G, 'profile_update', profile_update)
       rawset(_G, 'profile_delete', profile_delete)

       return true
   end
   ```

  **Примечание:** В этом коде мы используем Lua-функцию
  [rawset()](https://www.lua.org/manual/5.1/manual.html#pdf-rawset), чтобы
  задать значение полей в системном спейсе `_G`, который находится в
  области глобальных переменных, без вызова мета-методов.

А в конце нам необходимо экспортировать функции роли и зависимости из нашего
модуля:

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

## Роль http-сервера (`api`)

Сперва подключим все необходимые модули:

```lua
--app/roles/api.lua
local vshard = require('vshard')
local cartridge = require('cartridge')
local errors = require('errors')
local log = require('log')```
```

Далее создадим классы ошибок:

```lua
local err_vshard_router = errors.new_class("Vshard routing error")
local err_httpd = errors.new_class("httpd error")
```

Теперь реализуем основную логику:

1. Функции генерации ответа на http-запрос:

   ```lua
   local function json_response(req, json, status)
       local resp = req:render({json = json})
       resp.status = status
       return resp
   end

   local function internal_error_response(req, error)
       local resp = json_response(req, {
           info = "Internal error",
           error = error
       }, 500)
       return resp
   end

   local function profile_not_found_response(req)
       local resp = json_response(req, {
           info = "Profile not found"
       }, 404)
       return resp
   end

   local function profile_conflict_response(req)
       local resp = json_response(req, {
           info = "Profile already exist"
       }, 409)
       return resp
   end

   local function profile_unauthorized(req)
       local resp = json_response(req, {
           info = "Unauthorized"
       }, 401)
       return resp
   end

   local function storage_error_response(req, error)
       if error.err == "Profile already exist" then
           return profile_conflict_response(req)
       elseif error.err == "Profile not found" then
           return profile_not_found_response(req)
       elseif error.err == "Unauthorized" then
           return profile_unauthorized(req)
       else
           return internal_error_response(req, error)
       end
   end
   ```

2. Обработчик http-запроса на добавление профиля:

   ```lua
   local function http_profile_add(req)
       local profile = req:json()

       local bucket_id = vshard.router.bucket_id(profile.profile_id)
       profile.bucket_id = bucket_id

       local resp, error = err_vshard_router:pcall(
           vshard.router.call,
           bucket_id,
           'write',
           'profile_add',
           {profile}
       )

       if error then
           return internal_error_response(req, error)
       end
       if resp.error then
           return storage_error_response(req, resp.error)
       end

       return json_response(req, {info = "Successfully created"}, 201)
   end
   ```

     **Примечание:** В коде выше мы использовали Lua-функцию
     [pcall()](https://www.lua.org/manual/5.1/manual.html#pdf-pcall),
     чтобы вызвать функцию `err_vshard_router()` в защищенном режиме: `pcall()`
     ловит исключения, бросаемые функцией `err_vshard_router()`, и возвращает
     статус-код, не позволяя ошибкам пробрасываться наружу.

3. Обработчик http-запроса на изменение профиля:

   ```lua
   local function http_profile_update(req)
       local profile_id = tonumber(req:stash('profile_id'))
       local data = req:json()
       local changes = data.changes
       local password = data.password

       local bucket_id = vshard.router.bucket_id(profile_id)

       local resp, error = err_vshard_router:pcall(
           vshard.router.call,
           bucket_id,
           'read',
           'profile_update',
           {profile_id, password, changes}
       )

       if error then
           return internal_error_response(req,error)
       end
       if resp.error then
           return storage_error_response(req, resp.error)
       end

       return json_response(req, resp.profile, 200)
   end
   ```

4. Обработчик http-запроса на получение профиля:

   ```lua
   local function http_profile_get(req)
       local profile_id = tonumber(req:stash('profile_id'))
       local password = req:json().password
       local bucket_id = vshard.router.bucket_id(profile_id)

       local resp, error = err_vshard_router:pcall(
           vshard.router.call,
           bucket_id,
           'read',
           'profile_get',
           {profile_id, password}
       )

       if error then
           return internal_error_response(req, error)
       end
       if resp.error then
           return storage_error_response(req, resp.error)
       end

       return json_response(req, resp.profile, 200)
   end
   ```

5. Обработчик http-запроса на удаление профиля:

   ```lua
   local function http_profile_delete(req)
       local profile_id = tonumber(req:stash('profile_id'))
       local password = req:json().password
       local bucket_id = vshard.router.bucket_id(profile_id)

       local resp, error = err_vshard_router:pcall(
           vshard.router.call,
           bucket_id,
           'write',
           'profile_delete',
           {profile_id, password}
       )

       if error then
           return internal_error_response(req, error)
       end
       if resp.error then
           return storage_error_response(req, resp.error)
       end

       return json_response(req, {info = "Deleted"}, 200)
   end
   ```

6. Инициализация роли:

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

А в конце необходимо вернуть данные о роли:

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

В файле `init.lua` (в корне проекта) необходимо указать роли, которые будут
использоваться кластером:

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

## Тестирование

Напишем модульные и интеграционные тесты, проверяющие правильность работы нашего
приложения. Для написания тестов будем использовать `luatest`.

### Модульные тесты

Протестируем правильность работы отдельных модулей нашего приложения.
Файлы модульных тестов располагаются в папке `test/unit`.
Тесты для функций работы с данными профилей поместим в файл `storage_test.lua`.

```lua
-- storage_test.lua

local t = require('luatest')
local g = t.group('unit_storage_utils')
local helper = require('test.helper.unit')

require('test.helper.unit')


local storage = require('app.roles.storage')
local utils = storage.utils
local deepcopy = require('table').deepcopy
local auth = require('app.auth')

local test_profile = {
    profile_id = 1,
    bucket_id = 1,
    first_name = 'Petr',
    sur_name = 'Petrov',
    patronymic = 'Ivanovich',
    msgs_count = 100,
    service_info = 'admin'
}

local test_profile_no_shadow = deepcopy(test_profile)
test_profile_no_shadow.bucket_id = nil

local profile_password = 'qwerty'

local password_data = auth.create_password(profile_password)
test_profile.shadow = password_data.shadow
test_profile.salt = password_data.salt

g.test_sample = function()
    t.assert_equals(type(box.cfg), 'table')

end

g.test_profile_get_not_found = function()
    local res = utils.profile_get(1, profile_password)
    res.error = res.error.err
    t.assert_equals(res, {profile = nil, error = "Profile not found"})
end

g.test_profile_get_found = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    t.assert_equals(utils.profile_get(1, profile_password), {profile = test_profile_no_shadow, error = nil})
end

g.test_profile_get_unauthorized = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    local res = utils.profile_get(1, 'wrong_password')
    res.error = res.error.err
    t.assert_equals(res, {profile = nil, error = "Unauthorized"})
end

g.test_profile_add_ok = function()
    local to_insert = deepcopy(test_profile)
    to_insert.password = profile_password
    t.assert_equals(utils.profile_add(to_insert), {ok = true})
    to_insert.password = nil
    local from_space = box.space.profile:get(1)
    to_insert.shadow = from_space.shadow
    to_insert.salt = from_space.salt;
    t.assert_equals(from_space, box.space.profile:frommap(to_insert))
    t.assert_equals(auth.check_password(from_space, profile_password), true)
end

g.test_profile_add_conflict = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    local res = utils.profile_add(test_profile)
    res.error = res.error.err
    t.assert_equals(res, {ok = false, error = "Profile already exist"})
end

g.test_profile_update_ok = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))

    local changes = {
        msgs_count = 333,
        first_name = "Ivan"
    }

    local updated_profile = deepcopy(test_profile)
    updated_profile.msgs_count = changes.msgs_count
    updated_profile.first_name = changes.first_name
    local updated_no_shadow = deepcopy(test_profile_no_shadow)
    updated_no_shadow.msgs_count = changes.msgs_count
    updated_no_shadow.first_name = changes.first_name

    t.assert_equals(utils.profile_update(1, profile_password, changes), {profile = updated_no_shadow})
    t.assert_equals(box.space.profile:get(1), box.space.profile:frommap(updated_profile))
end

g.test_profile_update_not_found = function()
    local res = utils.profile_update(1, profile_password,{msgs_count = 111})
    res.error = res.error.err
    t.assert_equals(res, {profile = nil, error = res.error})
end

g.test_profile_update_unauthorized = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    local res = utils.profile_update(1, 'wrong_password', {msgs_count = 200})
    res.error = res.error.err
    t.assert_equals(res, {profile = nil, error = "Unauthorized"})
end

g.test_profile_update_password = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    local new_password = 'password'
    local res = utils.profile_update(1, profile_password, {password = new_password})
    t.assert_equals(res,{profile = test_profile_no_shadow})
    local profile = box.space.profile:get(1)
    t.assert_equals(auth.check_password(profile, new_password), true, 'incorrect shadow using profile salt')
end

g.test_profile_delete_ok = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    t.assert_equals(utils.profile_delete(1, profile_password), {ok = true})
    t.assert_equals(box.space.profile:get(1), nil, 'tuple must be deleted from space')
end

g.test_profile_delete_not_found = function()
    local res = utils.profile_delete(1, profile_password)
    res.error = res.error.err
    t.assert_equals(res, {ok = false, error = "Profile not found"})
end

g.test_profile_delete_unauthorized = function()
    box.space.profile:insert(box.space.profile:frommap(test_profile))
    local res = utils.profile_delete(1, 'wrong_password')
    res.error = res.error.err
    t.assert_equals(res, {ok = false, error = "Unauthorized"})
end

g.before_all(function()
    storage.init({is_master = true})
end)

g.before_each(function ()
    box.space.profile:truncate()
end)
```

### Интеграционные тесты

Для проверки правильности взаимодействий различных частей приложения напишем
интеграционные тесты. Во время тестирования запустим приложение и проверим
работоспособность с помощью http-запросов.

Настроить конфигурацию тестируемого приложения можно в файле
`test/helper/integration.lua`.

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

Для удобства дальнейшего тестирования здесь же опишем функцию, выполняющую
http-запрос к приложению и проверяющую правильность ответа.

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

В файле `test/integration/api_test.lua` напишем тесты:

```lua
--api_test.lua

local t = require('luatest')
local g = t.group('integration_api')

local helper = require('test.helper.integration')
local cluster = helper.cluster
local deepcopy = require('table').deepcopy

local test_profile = {
    profile_id = 1,
    first_name = 'Petr',
    sur_name = 'Petrov',
    patronymic = 'Ivanovich',
    msgs_count = 110,
    service_info = 'admin'
}

local user_password = 'qwerty'

g.test_sample = function()
    local server = cluster.main_server
    local response = server:http_request('post', '/admin/api', {json = {query = '{}'}})
    t.assert_equals(response.json, {data = {}})
    t.assert_equals(server.net_box:eval('return box.cfg.memtx_dir'), server.workdir)
end

g.test_on_get_not_found = function()
    helper.assert_http_json_request('get', '/profile/1', {password = user_password}, {body = {info = "Profile not found"}, status = 404})
end

g.test_on_post_ok = function ()
    local user_with_password = deepcopy(test_profile)
    user_with_password.password = user_password
    helper.assert_http_json_request('post', '/profile', user_with_password, {status=201})
end

g.test_on_post_conflict = function()
    local user_with_password = deepcopy(test_profile)
    user_with_password.password = user_password
    helper.assert_http_json_request('post', '/profile', user_with_password, {body = {info = "Profile already exist"}, status=409})
end

g.test_on_get_ok = function ()
    helper.assert_http_json_request('get', '/profile/1', {password = user_password}, {body = test_profile, status = 200})
end

g.test_on_get_unauthorized = function()
    helper.assert_http_json_request('get', '/profile/1', {password = 'passwd'}, {body = {info = "Unauthorized"}, status = 401})
end

g.test_on_put_not_found = function()
    helper.assert_http_json_request('put', '/profile/2', {password = user_password, changes ={msgs_count = 115}},
    {body = {info = "Profile not found"}, status = 404})
end

g.test_on_put_unauthorized = function()
    helper.assert_http_json_request('put', '/profile/1', {password = 'passwd', changes = {msgs_count = 115}},
    {body = {info = "Unauthorized"}, status = 401})
end

g.test_on_put_ok = function()
    local changed_profile = deepcopy(test_profile)
    changed_profile.msgs_count = 115
    helper.assert_http_json_request('put', '/profile/1', {password = user_password , changes = {msgs_count = 115}}, {body = changed_profile, status = 200})
end

g.test_on_delete_not_found = function ()
    helper.assert_http_json_request('delete', '/profile/2', {password = user_password}, {body = {info = "Profile not found"}, status = 404})
end

g.test_on_delete_unauthorized = function ()
    helper.assert_http_json_request('delete', '/profile/1', {password = 'passwd'}, {body = {info = "Unauthorized"}, status = 401})
end

g.test_on_delete_ok = function()
    helper.assert_http_json_request('delete', '/profile/1', {password = user_password}, {body = {info = "Deleted"}, status = 200})
end
```

Запустить тесты можно с помощью команды `.rocks/bin/luatest` в корневой
директории приложения.

## Запуск приложения

Можем запускать наш кластер!

Сначала соберем его:

```bash
profiles-storage $ tarantoolctl rocks make
```

Утилита `tarantoolctl` подтянет все указанные в `cache-scm-1.rockspec`
зависимости и подготовит кластер к запуску.

Теперь запустим кластер:

```bash
profiles-storage $ .rocks/bin/cartridge start
```

Подключимся к веб-интерфейсу, перейдя по адресу `http://127.0.0.1:8081/`
и сделаем следующее:

1. Назначим на одном инстансе роль `api`:

   ![](report_images/api-role.png)

2. Назначим на другом инстансе роль `storage`:

   ![](report_images/storage-role.png)

Должны создаться 2 набора реплик по одному инстансу Tarantool в каждом.

![](report_images/two-replicasets.png)

Теперь у нас есть 2 набора реплик с двумя ролями, но vshard еще не запущен.
Нажмем кнопку **Bootstrap vshard** на закладке **Cluster** в веб-интерфейсе.
Кластер готов к работе!

## Проверка работоспособности

Откроем новую консоль и добавим профиль через `curl`:

```bash
you@yourmachine$ curl -X POST -v -H "Content-Type: application/json" -d '{
"profile_id": 1,
"first_name": "Ivan",
"sur_name": "Ivnov",
"patronymic": "Ivanovich",
"password" : "qwerty",
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
> Content-Length: 156
>
* upload completely sent off: 156 out of 156 bytes
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

Проверим, что данные корректно сохранились в базе. Сделаем GET-запрос:

```bash
you@yourmachine$ curl -X GET -v http://localhost:8081/profile/1 -d '{"password" : "qwerty"}'
```

```bash
*   Trying 127.0.0.1:8081...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8081 (#0)
> GET /profile/1 HTTP/1.1
> Host: localhost:8081
> User-Agent: curl/7.65.3
> Accept: */*
> Content-Length: 23
> Content-Type: application/x-www-form-urlencoded
>
* upload completely sent off: 23 out of 23 bytes
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 Ok
< Content-length: 120
< Server: Tarantool http (tarantool v2.1.3-6-g91e2a9638)
< Content-type: application/json; charset=utf-8
< Connection: keep-alive
<
* Connection #0 to host localhost left intact
{"msgs_count":100,"patronymic":"Ivanovich","sur_name":"Ivnov","service_info":"admin","first_name":"Ivan","profile_id":1}
```

Исправим опечатку в фамилии пользователя с помощью PUT-запроса:

```bash
you@yourmachine$ curl -X PUT -v -H "Content-Type: application/json" -d '{ "password" : "qwerty", "changes" : {"sur_name": "Ivanov"}}' http://localhost:8081/profile/1
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
> Content-Length: 60
>
* upload completely sent off: 60 out of 60 bytes
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 Ok
< Content-length: 121
< Server: Tarantool http (tarantool v2.1.3-6-g91e2a9638)
< Content-type: application/json; charset=utf-8
< Connection: keep-alive
<
* Connection #0 to host localhost left intact
{"msgs_count":100,"patronymic":"Ivanovich","sur_name":"Ivanov","service_info":"admin","first_name":"Ivan","profile_id":1}
```

Изменим пароль пользователя:

```bash
you@yourmachine$ curl -X PUT -v -H "Content-Type: application/json" -d '{ "password" : "qwerty", "changes" : {"password": "password"}}' http://localhost:8081/profile/1
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
> Content-Length: 62
>
* upload completely sent off: 62 out of 62 bytes
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 Ok
< Content-length: 121
< Server: Tarantool http (tarantool v2.1.3-6-g91e2a9638)
< Content-type: application/json; charset=utf-8
< Connection: keep-alive
<
* Connection #0 to host localhost left intact
{"msgs_count":100,"patronymic":"Ivanovich","sur_name":"Ivanov","service_info":"admin","first_name":"Ivan","profile_id":1}
```

Попытаемся удалить этого пользователя с помощью DELETE-запроса,
используя старый пароль:

```bash
curl -X DELETE -v http://localhost:8081/profile/1 -d '{"password" : "qwerty"}'
```

Должны получить ответ `Unauthorized`:

```bash
*   Trying 127.0.0.1:8081...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8081 (#0)
> DELETE /profile/1 HTTP/1.1
> Host: localhost:8081
> User-Agent: curl/7.65.3
> Accept: */*
> Content-Length: 24
> Content-Type: application/x-www-form-urlencoded
>
* upload completely sent off: 24 out of 24 bytes
* Mark bundle as not supporting multiuse
< HTTP/1.1 401 Unauthorized
< Content-length: 23
< Server: Tarantool http (tarantool v2.1.3-6-g91e2a9638)
< Content-type: application/json; charset=utf-8
< Connection: keep-alive
<
* Connection #0 to host localhost left intact
{"info":"Unauthorized"}
```

Теперь удалим пользователя, используя новый пароль:

```bash
curl -X DELETE -v http://localhost:8081/profile/1 -d '{"password" : "password"}'
```

```bash
*   Trying 127.0.0.1:8081...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8081 (#0)
> DELETE /profile/1 HTTP/1.1
> Host: localhost:8081
> User-Agent: curl/7.65.3
> Accept: */*
> Content-Length: 25
> Content-Type: application/x-www-form-urlencoded
>
* upload completely sent off: 25 out of 25 bytes
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 Ok
< Content-length: 18
< Server: Tarantool http (tarantool v2.1.3-6-g91e2a9638)
< Content-type: application/json; charset=utf-8
< Connection: keep-alive
<
* Connection #0 to host localhost left intact
{"info":"Deleted"}
```

Убедимся, что пользователь был действительно удален:

```bash
you@yourmachine$ curl -X GET -v http://localhost:8081/profile/1 -d '{"password" : "password"}'
```

```bash
*   Trying 127.0.0.1:8081...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 8081 (#0)
> GET /profile/1 HTTP/1.1
> Host: localhost:8081
> User-Agent: curl/7.65.3
> Accept: */*
> Content-Length: 25
> Content-Type: application/x-www-form-urlencoded
>
* upload completely sent off: 25 out of 25 bytes
* Mark bundle as not supporting multiuse
< HTTP/1.1 404 Not found
< Content-length: 28
< Server: Tarantool http (tarantool v2.1.3-6-g91e2a9638)
< Content-type: application/json; charset=utf-8
< Connection: keep-alive
<
* Connection #0 to host localhost left intact
{"info":"Profile not found"}```
```

Отлично! Мы справились с задачей: реализовали хранилище профилей пользователей
с проверкой пароля, добавили тесты, проверили работоспособность.
