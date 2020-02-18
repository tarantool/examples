Пример №3 - Создание сервиса

# Подготовка к работе

Выполните установку TDG в соответствии с инструкцией по адресу https://www.tarantool.io/ru/tdg/1.5/deployment/.

Проверьте работоспособность TDG, открыв web-интерфейс по адресу
<http://ip-адрес:порт> (при развёртывании кластера с примером конфигурации из папки
`deploy` это, например http://172.19.0.2:8080, а для локально развернутого TDG это
http://localhost:8080), где

    * ip-адрес - это адрес сервера, где установлен любой экземпляр TDG,
    * порт - это http-порт любого из экземпляров TDG на этом сервере.

При входе в web-интерфейс свеже-установленного TDG авторизация не требуется, поэтому
вы увидите главное окно с навигационным меню слева.

По-умолчанию открывается вкладка **Cluster**, где можно выполнить настройку
кластера (назначить роли и настроить репликацию если они не были заданы в файле
конфигурации кластера при установке) для экземпляров кластера TDG. Подробнее -
в документации https://www.tarantool.io/ru/tdg/1.5/cluster_setup/#replicasets-roles-setup.

После выполнения первоначальной конфигурации кластера нажмите кнопку **Bootstrap vshard**
для инициализации распределённого хранилища данных.

## Подготовка установленного TDG к работе

Для завершения процесса запуска TDG в работу необходимо:
-- Задать доменную модель.
-- Загрузить конфигурацию и исполняемый код для обработки данных.

Все необходимые данные указываются в конфигурационном файле, включая ссылки на другие
файлы. Затем все необходимые файлы (конфигурационный файл и все упоминаемые в нём
файлы) запаковываются в ZIP архив и загружаются на странице **Configuration files**.
Далее приведено подробное описание данного процесса с указанием данных, используемых в примере.

### Доменная модель

Создайте файл `model.avsc` со следующим содержимым:

```json
[
    {
        "name": "Person",
        "type": "record",
        "logicalType": "Aggregate",
        "doc": "person",
        "fields": [
            {"name": "id", "type": "long"},
            {"name": "name", "type": "string"},
            {"name": "lastActivityDate", "type": ["null", "string"]}
        ],
        "indexes": ["id", "name", "lastActivityDate"]
    }
]
```
Подробнее о разработке доменной модели изложено в документации https://www.tarantool.io/ru/tdg/1.5/domain_model/.

### Конфигурация

Создайте конфигурационный файл `config.yml`, в котором заданы основные параметры
обработки данных: модель, функции, пайплайны, коннектор, входной и выходной процессоры.

```yml
types:
  __file: model.avsc

functions:
  router: {__file: router.lua}
  classifier: {__file: classificator.lua}
  delete_inactive_persons: {__file: delete_inactive_persons.lua}


pipelines:
  router:
    - router
  classifier:
    - classifier
  delete_inactive_persons:
    - delete_inactive_persons

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
    - key: add_person
      type: Person

services:
  delete_inactive_persons:
    doc: "delete_inactive_persons"
    function: delete_inactive_persons
    return_type: string
    args:
      threshold_date: string
```

### Исполняемый код

#### Роутер

Создайте файл `router.lua` со следующим содержимым:

```lua
#!/usr/bin/env tarantool

local param = ...

local ret = { obj = param, priority = 1, routing_key = 'input_key'}

return ret
```

Он выставляет всем входящим запросам `routing_key = 'input_key'`, адресующий
к входному процессору 'input_processor' (секция `connector / routing` в `config.yml`)

#### Классификатор

Создайте файл `classificator.lua` со следующим содержимым:

```lua
#!/usr/bin/env tarantool

local param = ...

if param.obj.id ~= nil then
  param.routing_key = "add_person"
  return param
end

param.routing_key = "unknown_type"
return param
```

Он выставляет ключ `routing_key = 'add_person'` при наличии у записи поля `id` и
`routing_key = "unknown_type"` во всех остальных случаях.

Подробнее про обработку запросов, не прошедших классификацию можно прочитать в
документации - https://www.tarantool.io/ru/tdg/1.5/repair_queue/.

#### Обработчик сервиса

Создайте файл `delete_inactive_persons.lua` следующего содержания:

```lua
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
```

В файле выше мы написали функцию удаления для записей, у которых `lastActivityDate` меньше
заданного.

### Загрузка конфигурации

Получившиеся файлы `model.avsc`, `config.yml`, `router.lua`, `classificator.lua` и
`delete_inactive_persons.lua` необходимо запаковать в архив формата ZIP.

Полученный архив необходимо перетащить мышкой в секцию **Upload configuration** на
вкладке **Configuration files**. После нажатия кнопки **Save** конфигурация должна
загрузиться в систему и начать отображаться на вкладке **Model**.

### Настройка доступа

Для полноценной работы с TDG вам понадобится создать пользователя и включить
авторизацию. Для выполнения запросов на чтение и запись данных, необходимо настроить
доступ к используемым агрегатам для используемого пользователя. Подробнее про выполнение
настроек безопасности указано в документации - https://www.tarantool.io/ru/tdg/1.5/security/.

Теперь TDG готов предоставить новый сервис.

# Использование сервиса

## Загрузка тестовых данных

Перейдите на вкладку **Test** и выполните слеующие три запроса:

Первый:
    ```json
    {
     "id": 1,
     "name": "John Smith",
     "lastActivityDate": "2020-01-11"
    }
    ```

Второй:
    ```json
    {
     "id": 2,
     "name": "Adam Sanders",
     "lastActivityDate": "2020-01-12"
    }
    ```

Третий:
    ```json
    {
     "id": 3,
     "name": "Deny Snider",
     "lastActivityDate": "2020-01-15"
    }
    ```

## Использование сервиса

Проверьте правильность работы сервиса с помощью `GraphQL`.
Перейдите на соответствующую вкладку и отправьте следующий GraphQL запрос:
    ```graphql
    {
     delete_inactive_persons(threshold_date: "2020-01-14")
    }
    ```

Ответ будет выглядеть примерно следующим образом:
    ```graphql
    {
     "data": {
      "delete_inactive_persons": "[{\"lastActivityDate\":\"2020-01-12\",\"name\":\"Adam Sanders\",\"id\":2},{\"lastActivityDate\":\"2020-01-11\",\"name\":\"John Smith\",\"id\":1}]"
     }
    }
    ```
Это означает, что удалены записи с `lastActivityDate` "2020-01-11" и "2020-01-12".

Для проверки выполните следующий простой запрос на выборку всех записей:
    ```graphql
    {
     Person {
      id
      name
      lastActivityDate
     }
    }
    ```

Ответ будет выглядеть примерно так:
    ```graphql
    {
     "data": {
      "Person": [
        {
         "lastActivityDate": "2020-01-15",
         "name": "Deny Snider",
         "id": 3
        }
      ]
     }
    }
    ```

## Доработка корректного вывода

Получившийся результат в целом соответствует задумке. Однако, внимательный пользователь
заметит - ответ на GraphQL запрос для вызова сервиса и удаления записей был сформирован
не вполне корректно. В него попал JSON с **key** соответствующим имени вызванной
функции и **value** соответствующим выводу функции ``repository.delete``, отфильтрованному
по полям ``id``, ``name`` и ``lastActivityDate`` и представленному в виде длинной
строки. Кроме того, символы кавычек ``"`` представлены в выводимой строке с изолирующей
косой чертой - ``\"``.

Для вывода корректного и формализованного ответа на GraphQL запрос выполните следующие
изменения.

### Доработка файла конфигурации

Отредактируйте раздел ``services`` файла `config.yml` следующим образом:

```yml
services:
  delete_inactive_persons:
    doc: "delete_inactive_persons"
    function: delete_inactive_persons
    return_type:
      type: array
      items: Person
    args:
      threshold_date: string
```

Это укажет TDG на то, что вывод сервиса ``delete_inactive_persons`` должен быть
представлен в формате массива из объектов типа ``Person`` имеющейся модели данных.

### Доработка обработчика сервиса

Отредактируйте файл `delete_inactive_persons.lua` так, чтобы он имел следующее содержание:

```lua
local param = ...
local threshold_date = param.threshold_date

local deleted_persons = repository.delete('Person', {{"$lastActivityDate", "<", threshold_date}})

return deleted_person
```

### Загрузка конфигурации

Получившиеся файлы `model.avsc`, `config.yml`, `router.lua`, `classificator.lua` и
`delete_inactive_persons.lua` необходимо снова запаковать в архив формата ZIP.

Полученный архив необходимо перетащить мышкой в секцию **Upload configuration** на
вкладке **Configuration files**. После нажатия кнопки **Save** конфигурация должна
загрузиться в систему и начать отображаться на вкладке **Model**.

## Проверка изменений в сервисе

Теперь снова добавьте в систему данные, которые будем удалять.

### Загрузка тестовых данных

Перейдите на вкладку **Test** и выполните следующие два запроса:

Первый:
    ```json
    {
     "id": 1,
     "name": "John Smith2",
     "lastActivityDate": "2020-01-11"
    }
    ```

Второй:
    ```json
    {
     "id": 2,
     "name": "Adam Sanders2",
     "lastActivityDate": "2020-01-12"
    }
    ```

### Использование сервиса

Повторно проверьте правильность работы сервиса с помощью `GraphQL`.
Перейдите на соответствующую вкладку и отправьте следующий GraphQL запрос:
    ```graphql
    {
     delete_inactive_persons(threshold_date: "2020-01-14")
    {id
     name
     lastActivityDate
    }
    }
    ```

Теперь ответ будет выглядеть примерно следующим образом:
    ```graphql
    {
      "data": {
        "delete_inactive_persons": [
          {
            "lastActivityDate": "2020-01-12",
            "name": "Adam Sanders2",
            "id": 2
          },
          {
            "lastActivityDate": "2020-01-11",
            "name": "John Smith2",
            "id": 1
          }
        ]
      }
    }
    ```

Обратите внимание, GraphQL запрос был выполнен с указанием конкретных полей объекта -
``id``, ``name`` и ``lastActivityDate``, которые и были выведены в ответе.


