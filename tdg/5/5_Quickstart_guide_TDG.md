Пример №5 - Affinity и локальная обработка на узле

# Подготовка к работе

Выполните установку TDG в соответствии с инструкцией по адресу https://www.tarantool.io/ru/tdg/1.5/deployment/.

Проверьте работоспособность TDG, открыв web-интерфейс по адресу
<http://ip-адрес:порт> (при развёртывании кластера с примером конфигурации из папки
`deploy` это, например, http://172.19.0.2:8080, а для локально развернутого TDG это
http://localhost:8080), где

* `ip-адрес` — это адрес сервера, где установлен любой экземпляр TDG,
* `порт` — это http-порт любого из экземпляров TDG на этом сервере.

При входе в web-интерфейс свеже-установленного TDG авторизация не требуется, поэтому
вы увидите главное окно с навигационным меню слева.

По умолчанию открывается вкладка **Cluster**, где можно выполнить настройку
кластера (назначить роли и настроить репликацию если они не были заданы в файле
конфигурации кластера при установке) для экземпляров кластера TDG. Подробнее —
в документации https://www.tarantool.io/ru/tdg/1.5/cluster_setup/#replicasets-roles-setup.

После выполнения первоначальной конфигурации кластера нажмите кнопку **Bootstrap vshard**
для инициализации распределённого хранилища данных.

## Подготовка установленного TDG к работе

Для завершения процесса запуска TDG в работу необходимо:
* задать доменную модель,
* загрузить конфигурацию и исполняемый код для обработки данных.

Все необходимые данные указываются в конфигурационном файле, включая ссылки на другие
файлы. Затем все необходимые файлы (конфигурационный файл и все упоминаемые в нём
файлы) запаковываются в ZIP архив и загружаются на странице **Configuration files**.
Далее приведено подробное описание данного процесса с указанием данных, используемых в примере.

### Доменная модель

Опишем сущности `User`, `Subscription` и `Book` (Читатель, Абонемент и Книга
соответственно). `User` и `Book` имеют отношение "многие ко многим" и связаны через
объект `Subscription` (как через таблицу в табличных СУБД).

В общем случае, данные распределяются по "бакетам" с использованием хэш-функции
от первичного ключа. Подробнее в документации https://www.tarantool.io/ru/doc/2.2/reference/reference_rock/vshard/vshard_architecture/#vshard-vbuckets.

Однако, иногда хочется получить данные с одного "бакета",
не делая выборку по всему кластеру (`map_reduce`). Для этого следует определить
поле `affinity` в модели данных с требуемым значением
первичного ключа. В нашем примере с сущностью `Subscription` сделаем распределение
по полю `user_id`. Данный подход значительно ускоряет поиск.

Создайте файл `model.avsc` со следующим содержимым:

```json
[
    {
        "name": "User",
        "type": "record",
        "logicalType": "Aggregate",
        "doc": "читатель",
        "fields": [
            {"name": "id", "type": "long"},
            {"name": "username", "type": "string"}
        ],
        "indexes": ["id"],
        "relations": [
          { "name": "subscription", "to": "Subscription", "count": "many", "from_fields": "id", "to_fields": "user_id" }
        ]
    },
    {
        "name": "Book",
        "type": "record",
        "logicalType": "Aggregate",
        "doc": "книга",
        "fields": [
            {"name": "id", "type": "long"},
            {"name": "book_name", "type": "string"},
            {"name": "author", "type": "string"}
        ],
        "indexes": ["id"],
        "relations": [
          { "name": "subscription", "to": "Subscription", "count": "many", "from_fields": "id", "to_fields": "book_id" }
        ]
    },
    {
    "name": "Subscription",
    "type": "record",
    "logicalType": "Aggregate",
    "doc": "абонемент",
    "fields": [
        {"name": "id", "type": "long"},
        {"name": "user_id", "type": "long"},
        {"name": "book_id", "type": "long"}
    ],
    "indexes": [
      {"name":"pkey", "parts": ["id", "user_id"]},
      "user_id",
      "book_id"
    ],
    "affinity": "user_id",
    "relations": [
      { "name": "user", "to": "User", "count": "one", "from_fields": "user_id", "to_fields": "id" },
      { "name": "book", "to": "Book", "count": "one", "from_fields": "book_id", "to_fields": "id" }
    ]
    }
]
```
Обратите внимание на индекс `pkey` и поле `"affinity": "user_id"`.

Подробнее про поле `affinity` можно прочитать в документации: https://www.tarantool.io/ru/tdg/1.5/domain_model/#id13.
Подробнее о разработке доменной модели: https://www.tarantool.io/ru/tdg/1.5/domain_model/.

### Конфигурация

Создайте конфигурационный файл `config.yml`, в котором заданы основные параметры
обработки данных: модель, функции, пайплайны, коннектор, входной и выходной процессоры.
В нём мы опишем сервис `select_user_books`.

```yml
types:
  __file: model.avsc

functions:
  router: {__file: router.lua}

  classifier: {__file: classificator.lua}

  select_user_books: {__file: select_user_books.lua}

pipelines:
  router:
    - router
  classifier:
    - classifier
  select_user_books:
    - select_user_books

connector:
  input:
    - name: http
      type: http
      pipeline: router

  routing:
    - key: input_key
      output: to_input_processor

  output:
    - name: to_input_processor
      type: input_processor

input_processor:
  classifiers:
    - name: classifier
      pipeline: classifier

  storage:
    - key: add_user
      type: User
    - key: add_book
      type: Book
    - key: add_subscription
      type: Subscription

services:
  select_user_books:
    doc: "select_user_books"
    function: select_user_books
    return_type: string
    args:
      user_id: long
```

### Исполняемый код

#### Роутер

Создайте файл `router.lua` со следующим содержимым:

```lua
#!/usr/bin/env tarantool

local param = ...

local ret = {obj = param, priority = 1, routing_key = 'input_key'}

return ret
```

Он выставляет всем входящим запросам `routing_key = 'input_key'`, адресующий
к входному процессору `input_processor` (секция `connector / routing` в `config.yml`).

#### Классификатор

Создайте файл `classificator.lua` со следующим содержимым:

```lua
#!/usr/bin/env tarantool

local param = ...

if param.obj.username ~= nil then
    param.routing_key = "add_user"
    return param
end

if param.obj.book_name ~= nil then
    param.routing_key = "add_book"
    return param
end

if (param.obj.user_id ~= nil and param.obj.book_id ~= nil) then
    param.routing_key = "add_subscription"
    return param
end

param.routing_key = "unknown_type"
return param
```

Он выставляет ключ:
* `routing_key = 'add_user'` при наличии у записи поля `username`,
* `routing_key = 'add_book'` при наличии у записи поля `book_name`,
* `routing_key = 'add_subscription'` при наличии у записи полей `user_id` и `book_id`,
* а также `routing_key = "unknown_type"` во всех остальных случаях.

#### Обработчик

Создайте файл `select_user_books.lua` со следующим содержимым:
```lua
local param = ...
local user_id = param.user_id

local user_books = repository.find('Subscription', {{"$user_id", "==", user_id}})

local result = {}
for _, book in pairs(user_books) do
    table.insert(result, book.book_id)
end

return json.encode(result)
```

Он выполняет поиск по хранящимся данным при помощи функции программного интерфейса репозитория.
Подробнее про его функции читайте в документации - https://www.tarantool.io/ru/tdg/1.5/repository_api/.

Подробнее про обработку запросов, не прошедших классификацию можно прочитать в
документации - https://www.tarantool.io/ru/tdg/1.5/repair_queue/.

### Загрузка конфигурации

Получившиеся файлы `model.avsc`, `config.yml`, `router.lua`, `classificator.lua`
и `select_user_books.lua` необходимо запаковать в архив формата ZIP.

Полученный архив необходимо перетащить мышкой в секцию **Upload configuration** на
вкладке **Configuration files**. После нажатия кнопки **Save** конфигурация должна
загрузиться в систему и начать отображаться на вкладке **Model**.

### Настройка доступа

Для полноценной работы с TDG вам понадобится создать пользователя и включить
авторизацию. Для выполнения запросов на чтение и запись данных, необходимо настроить
доступ к используемым агрегатам для используемого пользователя. Подробнее про выполнение
настроек безопасности указано в документации - https://www.tarantool.io/ru/tdg/1.5/security/.

Теперь TDG готов выполнять запросы и предоставлять сервис выборки.

# Использование сервиса локальной выборки

Теперь, если нам нам потребуется найти все книги, которые взял пользователь с
заданным `user_id`, будут выбраны записи из одного из "бакетов", вместо обхода
кластера (при котором используется функция программного интерфейса репозитория "map_reduce")
с поиском записей с данным значением поля `user_id`.

## Загрузка тестовых данных

Загрузите несколько объектов в систему, используя следующие команды.

Для загрузки пользователей:

Первый
```json
{
 "id": 1,
 "username": "John Smith"
}
```

Второй
```json
{
 "id": 2,
 "username": "Adam Sanders"
}
```

Для загрузки книг:

Первая
```json
{
 "id": 1,
 "book_name": "Fight Club",
 "author": "Chack Palanick"
}
```

Вторая
```json
{
 "id": 2,
 "book_name": "The Revenant: a novel of revenge",
 "author": "Michael Punke"
}
```

Третья
```json
{
 "id": 3,
 "book_name": "The Great Gatsby",
 "author": "F.S. Fitzgerald"
}
```

Для загрузки абонементов:

Первый
```json
{
 "id": 1,
 "user_id": 1,
 "book_id": 1
}
```

Второй
```json
{
 "id": 2,
 "user_id": 1,
 "book_id": 3
}
```

## Проверка работы сервиса

Проверить правильность работы сервиса можно с помощью `GraphQL`.

Перейдите на соответствующию вкладку и отправьте следующий GraphQL-запрос:
```graphql
{
 select_user_books(user_id: 1)
}
```

Ответ будет выглядеть примерно так (`id` книг которые взял пользователь с `user_id`=1):
```graphql
{
 "data": {
   "select_user_books": "[1, 3]"
 }
}
```
