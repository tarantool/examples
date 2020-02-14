Пример №2 - Загрузка данных извне

# Подготовка к работе

Выполните установку TDG в соответствии с инструкцией по адресу https://www.tarantool.io/ru/tdg/1.5/deployment/.

Проверьте работоспособность TDG, открыв web-интерфейс по адресу
<http://ip-адрес:порт> (при развёртывании кластера с примером конфигурации из папки
`deploy` это, например http://172.19.0.2:8080, а для локально развернутого TDG это
http://localhost:8080), где

    * ip-адрес - это адрес сервера, где установлен любой экземпляр TDG,
    * порт - это http-порт любого из экземпляров TDG на этом сервере.

При входе в web-интерфейс свежеустановленного TDG авторизация не требуется, поэтому
вы увидите главное окно с навигационным меню слева.

По-умолчанию открывается вкладка **Cluster**, где можно выполнить настройку
кластера (назначить роли и настроить репликацию если они не были заданы в файле
конфигурации кластера при установке) для экземпляров кластера TDG. Подробнее -
в документации https://www.tarantool.io/ru/tdg/1.5/cluster_setup/#replicasets-roles-setup.

После выполнения первоначальной конфигурации кластера нажмите кнопку **Bootstrap vshard**
для инициализации распределнного хранилища данных.

## Подготовка установленного TDG к работе

Для завершения процесса запуска TDG в работу необходимо:
-- Задать доменную модель.
-- Загрузить конфигурацию и исполняемый код для обработки данных.

Все необходимые данные указываются в конфигурационном файле, включая ссылки на другие
файлы. Затем все необходимые файлы (конфигурационный файл и все упоминаемые в нём
файлы) запаковываются в ZIP архив и загружаются на странице **Configuration files**.
Далее приведено подробное описание данного процесса с указанием данных, использумых в примере.

### Доменная модель

Создайте файл `model.avsc` со следующим содержимым:

```json
[
  {
    "name": "Account",
    "type": "record",
    "logicalType": "Aggregate",
    "doc": "User's account",
    "fields": [
      {"name": "id", "type": "string"},
      {"name": "name", "type": ["null", "string"], "default": null}
    ],
    "indexes": ["id"]
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

  account_handler: {__file: account_handler.lua}

pipelines:
  router:
    - router
  classifier:
    - classifier
  account_handler:
    - account_handler

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

  routing:
    - key: account_key
      pipeline: account_handler

  storage:
    - key: account_key
      type: Account
```

Для данного примера нужно обратить внимание на настройку коннектора.
Входной коннектор получает входящий запрос и выполняет его первоначальную обработку.
Параметр `type` в разделе  `input` позволяет выбрать тип обрабатываемого коннектором запроса:
* `http` -- JSON via HTTP,
* `soap` -- SOAP(XML) via HTTP,
* `kafka`-- Kafka.

### Исполняемый код

Исполняемый код для данного примера размещается в файлах `account_handler.lua`,
`classifier.lua` и `router.lua`. Содержимое этих файлов приведено далее.

#### Роутер

Создайте файл `router.lua` со следующим содержимым:

```lua
#!/usr/bin/env tarantool

local param = ...

local ret = {obj = param, priority = 1, routing_key = 'input_key'}

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
  param.routing_key = "account_key"
  return param
end

param.routing_key = "unknown_input"
return param
```

Он выставляет ключ `routing_key = 'account_key'` при наличии у записи поля `id` и
`routing_key = "unknown_type"` во всех остальных случаях.

Подробнее про обработку запросов, не прошедших классификацию можно прочитать в
документации - https://www.tarantool.io/ru/tdg/1.5/repair_queue/.

#### Обработчик

Создайте файл `account_handler.lua` со следующим содержимым:

```lua
#!/usr/bin/env tarantool

local param = ...

param.obj.name = param.obj.first_name .. ' ' .. param.obj.last_name
param.obj.first_name = nil
param.obj.last_name = nil

param.routing_key = "account_key"

return param
```

Он выполняет обработку информации. В данном случае создает новое поле `name` при
помощи конкатенации строк `first_name` и `last_name`, а также обнуляет эти исходные
строки, что равносильно их удалению. Таким обарзом в TDG будет сохранён лишь результат
обработки запроса, но не исходная информация.

Так же здесь продемонстрировано задание ключа `routing_key = "account_key"`,
однако это сделано в целях демонстрации таковой возможности, поскольку данному
запросу уже был присвоен этот ключ на предыдущем этапе обработки (в классификаторе).

Следует обратить внимание, что в данном примере предполагается обрабатывать запросы,
которые приходят в следующем виде:

```lua
{
  "id": id,
  "first_name": first_name,
  "last_name": last_name
}
```

### Загрузка конфигурации

Получившиеся файлы `model.avsc`, `config.yml`, `router.lua`, `classificator.lua`
и `account_handler.lua` необходимо запаковать в архив формата ZIP.

Полученный архив необходимо перетащить мышкой в секцию **Upload configuration** на
вкладке **Configuration files**. После нажатия кнопки **Save** конфигурация должна
загрузиться в систему и начать отображаться на вкладке **Model**.

### Настройка доступа

Для полноценной работы с TDG вам понадобится создать пользователя и включить
авторизацию. Для выполнения запросов на чтение и запись данных, необходимо настроить
доступ к использумым агрегатам для используемого пользователя. Поскольку мы будем
загружать данные из внешней системы, то необходимо зайти на вкладку **Tokens** и
создать новый Токен приложений. Подробнее про Токен приложений и выполнение
настроек безопасности указано в документации - https://www.tarantool.io/ru/tdg/1.5/security/.

Теперь TDG готов выполнять запросы и обрабатывать информацию.

# Загрузка нового объекта

### Загрузка объекта с помощью Python

C помощью интерпретатора языка Python и модуля `requests` загрузим объект в систему.
Далее приведён исходный код скрипта на языке Python для загрузки нового объекта в
настроенный ранее кластер TDG (замените адрес `http://localhost:8080/` адресом
установки экземпляра с ролью **connector** вашего кластера TDG, а число-буквенный
код `ee7fbd80-a9ac-4dcf-8e43-7c98a969c33c` - токеном приложения, созданным ранее):

``` python
import requests

account = {"id": "1", "first_name": "Alex", "last_name": "Smith"}
header = {'auth-token' : 'ee7fbd80-a9ac-4dcf-8e43-7c98a969c33c'}

r = requests.post(url = "http://172.19.0.2:8080/http", json = account, headers = header)
```

Теперь во вкладке **Graphql** веб интерфейса TDG проверьте наличие загруженного объекта:

```
{
  Account(id: "1"){
    name
  }
}
```

Ответ на запрос должен быть похожим на следующий пример:

```
{
  "data": {
    "Account": [
      {
        "name": "Alex Smith"
      }
    ]
  }
}
```

Это означает, что JSON переданный Python-скриптом был успешно обработан TDG.
