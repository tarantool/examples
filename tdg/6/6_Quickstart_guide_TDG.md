Пример №6 - Взаимодействие с Kafka

# Подготовка к работе

Для запуска примера используется виртуальная машина CentOS 7, поднятая c использованием Vagrant.

В примере описаны три контейнера, которые нужны для минимальной настройки подключения к Kafka, — Tarantool Data Grid,
[Zookeeper](https://zookeeper.apache.org/) и брокер (сервер) Kafka. Контейнеры развернуты с помощью 
[Docker Compose](https://docs.docker.com/compose/).

Пример можно использовать в качестве песочницы, если возникла необходимость воспроизвести в тестовом режиме ошибки, 
связанные с Kafka.

## Установка и запуск Vagrant

1. Установите [VirtualBox](https://www.virtualbox.org/) и [Vagrant](https://www.vagrantup.com/).
2. В папке с примером находится файл конфигурации `Vagrantfile`. Перейдите в директорию с `Vagrantfile`:

    ```
    cd examples/tdg/6/
    ```

3. Запустите развертывание виртуальной машины:

    ```
    vagrant up
    ```
4. Подключитесь к контейнеру:

    ```
    vagrant ssh
    ```

## Подготовка к запуску Docker-контейнеров

1. Установите необходимые пакеты:

    ```
    sudo su
    yum install python3-devel python3 awscli gcc-c++
    sudo curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/bin/docker-compose
    chmod +x /usr/bin/docker-compose
    systemctl enable docker
    systemctl start docker
    docker network create examplekafka
    ```

2. Подготовьте Docker-образ для TDG:
Скачайте образ из AWS 
    - Прописываем креды для AWS
    ```
    export AWS_ACCESS_KEY_ID=
    export AWS_SECRET_ACCESS_KEY=
    ```
    - Качаем сборку
    ```
    aws s3 --endpoint-url="https://hb.bizmrg.com" cp s3://packages/tdg2/tdg-2.6.1-0-g1c1b9863-docker-image.tar.gz /tmp
    ```
    - Устанавливаем
    ```
    sudo su
    cd /tmp
    docker load -i ./tdg-2.6.1-0-g1c1b9863-docker-image.tar.gz
    ```
   
## Запуск TDG

Разверните контейнер с TDG, используя Docker Compose:

  ```
  sudo su
  cd /app
  docker-compose up
  ```

Проверьте работоспособность TDG, открыв web-интерфейс по адресу
http://localhost:28080/admin/cluster/dashboard.

При входе в web-интерфейс TDG авторизация не требуется, поэтому
вы увидите главное окно с навигационным меню слева. По умолчанию открывается вкладка **Cluster**, где можно выполнить настройку
кластера (назначить роли и настроить репликацию, если они не были заданы в файле
конфигурации кластера при установке) для экземпляров кластера TDG. Подробнее о настройке кластера можно прочитать
в документации https://www.tarantool.io/ru/tdg/latest/administration/deployment/ansible-deployment/#ansible-deploy-topology.

После выполнения первоначальной конфигурации кластера нажмите кнопку **Bootstrap vshard**
для инициализации распределённого хранилища данных.

## Подготовка установленного TDG к работе

Для завершения процесса запуска TDG в работу необходимо:
* задать доменную модель;
* загрузить конфигурацию и исполняемый код для обработки данных.

Все необходимые данные указываются в конфигурационном файле, включая ссылки на другие
файлы. Затем все необходимые файлы (конфигурационный файл и все упоминаемые в нём
файлы) и загружаются в TDG.
Далее приведено подробное описание данного процесса с указанием данных, используемых в примере.

### Доменная модель

Создайте файл `model.avsc` со следующим содержимым:

```json
[
    {
    	"type": "record",
    	"name": "test_space",
    	"fields": [
    		{
    			"name": "id",
    			"type": "long"
    		},
    		{
    		    "name": "space_field_data",
    			"type": ["null","string"]
    		}
    	],
    	"indexes": [
    		{
    	    	"name": "pk",
    			"parts": [
    				"id"
    			]
    		}
    	]
    }
]
```

В модели описан объект `test_space`, который содержит два поля:

* `id` — идентификатор записи;
* `space_field_data` — данные кортежа.

### Конфигурация

Создайте конфигурационный файл `config.yml`, в котором заданы основные параметры
обработки данных: модель, функции, коннектор, входной (input) и выходной (output) обработчики, а также сервис
`kafka_service`.

```yml
types:
  __file: model.avsc

connector:
  input:
    - name: http
      type: http
    - name: kafka
      type: kafka
      brokers:
        - kafka-broker:9092
      topics:
        - in.test.topic
      group_id: kafka
      options:
        enable.auto.offset.store: "true"
        auto.offset.reset: "latest"
        enable.partition.eof: "false"
        security.protocol: "plaintext"

  output:
    - name: to_kafka
      type: kafka
      brokers:
        - kafka-broker:9092
      topic: out.test.topic
      group_id: kafka
      options:
        enable.auto.offset.store: "true"
        auto.offset.reset: "latest"
        enable.partition.eof: "false"
        security.protocol: "plaintext"

services:
  sendkafka:
    function: kafka_service.call
    return_type: ["null","string"]
    args:
        input: string
```

### Обработчик

Создайте файл `kafka_service.lua` со следующим содержимым:

```lua
local log = require('log')
local json = require('json')

local connector = require('connector')

local function call(par)
    log.info(json.encode(par))
    connector.send("to_kafka", par, {})
    return "ok"
end

return {
    call = call,
}
```

### Загрузка конфигурации

Чтобы загрузить файлы конфигурации в TDG, воспользуйтесь одним из способов ниже:

* В папке с примером №6 находится скрипт `setconfig.py`. Чтобы загрузить конфигурацию, запустите этот скрипт, используя
следующую команду:

      ```
      cd /app
      python3 ./setconfig.py
      ```

* Создайте папку `src` и поместите в нее файл со скриптом обработчика (`kafka_service.lua`). После этого упакуйте файлы
`model.avsc`,`config.yml` и созданную папку `src` в архив формата ZIP. В веб-интерфейсе TDG перейдите на вкладку
`Configuration files`, нажмите на кнопку `Upload a new config` и загрузите архив. Файлы будут распакованы и применены.

В этом примере для загрузки рекомендуется использовать скрипт.
