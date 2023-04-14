Пример №6 - Взаимодействие с Kafka

В примере описано, как настроить подключение к Kafka и проверить его
в приложении [Kafka Offset Explorer](https://www.kafkatool.com/download.html).
Кроме того, пример можно использовать в качестве песочницы, если вы хотите воспроизвести в тестовом режиме ошибки,
возникающие при [работе с Kafka](https://www.tarantool.io/ru/tdg/latest/development/kafka/troubleshoot-kafka/).

Содержание:

1. [Развертывание](#deployment)
    1. [Настройка виртуальной машины](#vm-setup)
    2. [Подготовка Docker-контейнеров](#docker-setup)
       1. [Загрузка Docker-образа](#docker-load)
       2. [Генерация SSL-сертификатов и запуск Docker-контейнеров](#ssl-gen)
2. [Конфигурация TDG](#tdg-config)
    1. [Доменная модель](#data-model)
    2. [Конфигурация](#config-file)
    3. [Исполняемые файлы](#lua-files)
        1. [Сервис](#lua-files1)
        2. [Обработчик](#lua-files2)
    4. [Загрузка конфигурации](#load-config)
3. [Установка и настройка Offset Explorer](#offset-exp-install)
   1. [Настройка Offset Explorer без SSL](#offset-exp-setup)
   2. [Настройка Offset Explorer c SSL](#offset-exp-setup-ssl)
4. [Работа в Offset Explorer](#offset-explorer)
    1. [Отправка сообщения в топик](#offset-exp-sendtotopic)
    2. [Отправка сообщения напрямую в Kafka](#offset-exp-sendtokafka)
5. [Воспроизведение ошибок, связанных с Kafka](#troubleshooting)
    1. [Неверно указан брокер](#kafka-broker)
    2. [Несуществующий топик или раздел](#kafka-topic)
    
# Развертывание <a name="deployment"></a>

В руководстве для запуска примера используется виртуальная машина CentOS 7, поднятая c использованием [Vagrant](https://www.vagrantup.com).

В примере описаны три контейнера, которые нужны для минимальной настройки подключения к Kafka, — Tarantool Data Grid,
[Zookeeper](https://zookeeper.apache.org/) и брокер (сервер) Kafka. Контейнеры развернуты с помощью 
[Docker Compose](https://docs.docker.com/compose/).

## Настройка виртуальной машины <a name="vm-setup"></a>

1. Установите [VirtualBox](https://www.virtualbox.org/) и [Vagrant](https://www.vagrantup.com/).
2. В папке с примером находится файл конфигурации `Vagrantfile`. Перейдите в директорию с этим файлом:

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

## Подготовка Docker-контейнеров <a name="docker-setup"></a>

### Загрузка Docker-образа <a name="docker-load"></a>

Установите необходимые пакеты:

```
sudo su
yum install python3-devel python3 awscli gcc-c++
sudo curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/bin/docker-compose
chmod +x /usr/bin/docker-compose
systemctl enable docker
systemctl start docker
docker network create examplekafka
```

Затем скачайте Docker-образ для TDG из AWS. Для этого:

1. Пропишите credentials для AWS:

    ```
    export AWS_ACCESS_KEY_ID=
    export AWS_SECRET_ACCESS_KEY=
    ```

2. Скачайте сборку:
    
    ```
    aws s3 --endpoint-url="https://hb.bizmrg.com" cp s3://packages/tdg2/tdg-2.6.1-0-g1c1b9863-docker-image.tar.gz /tmp
    ```

3. Загрузите образ TDG:

    ```
    sudo su
    cd /tmp
    docker load -i ./tdg-2.6.1-0-g1c1b9863-docker-image.tar.gz
    ```

### Генерация SSL-сертификатов и запуск Docker-контейнеров <a name="ssl-gen"></a>

Перед началом работы сгенерируйте SSL-сертификаты в контейнере `zookeeper-server`. Для этого выполните следующие команды:

```
sudo su
cd /app
mkdir truststore
mkdir keystore
chmod 777 ./truststore ./keystore

docker-compose up -d zookeeper-server
docker exec -it zookeeper-server bash -c "cd /app && ./generatecert.sh"
```

Команды развернут контейнер `zookeeper-server` и запустят скрипт для генерации SSL-сертификатов.

После запустите остальные контейнеры:

```
docker-compose up -d
```

## Конфигурация TDG <a name="tdg-config"></a>

1. После запуска Docker-контейнеров откройте [веб-интерфейс TDG](http://localhost:28080/admin/cluster/dashboard).
2. Назначьте роли в кластере TDG. Подробнее о настройке кластера можно прочитать
в [соответствующем разделе](https://www.tarantool.io/ru/tdg/latest/administration/deployment/ansible-deployment/#ansible-deploy-topology) документации.
3. После настройки кластера нажмите кнопку **Bootstrap vshard**, чтобы инициализировать распределённое хранилище данных.

Чтобы завершить настройку TDG, нужно:
* задать доменную модель и конфигурацию;
* загрузить конфигурацию и исполняемый код для обработки данных в TDG.

В конфигурационном файле нужно указать все необходимые данные, включая ссылки на другие файлы.
После файл конфигурации и все упомянутые в нем файлы загружаются в TDG.
Ниже пошагово демонстрируется процесс настройки файлов, необходимых для примера, и их загрузка в TDG. 

## Доменная модель <a name="data-model"></a>

Создайте файл `model.avsc`:

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

## Конфигурация <a name="config-file"></a>

Создайте конфигурационный файл `config.yml`. В файле задаются основные параметры
обработки данных:
* модель,
* функции,
* коннектор,
* входной (input) и выходной (output) обработчики,
* сервис `kafka_service`.

```yml
types:
  __file: model.avsc

services:
    sendkafka:
      function: kafka_service.call
      return_type: ["null","string"]
      args:
          input: string

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

    - name: kafkaProcessor
      type: kafka
      brokers:
        - kafka-broker:49092
      topics:
        - in.test.processor
      group_id: kafka
      options:
        enable.auto.offset.store: "true"
        auto.offset.reset: "earliest"
        enable.partition.eof: "false"

        enable.ssl.certificate.verification: "false"
        security.protocol: "ssl"

        ssl.certificate.location: /tmp/keystore/kafka-broker1.cer.pem
        ssl.key.location: /tmp/keystore/kafka-broker1.key.pem
        ssl.ca.location: /tmp/truststore/ca-cert.pem
        ssl.key.password: secret
  
      routing_key: kafka_key

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

input_processor:
  handlers:
    - key: kafka_key
      function: kafka_service.processor

```

## Исполняемые файлы <a name="lua-files"></a>

### Сервис <a name="lua-files1"></a>

Создайте сервис `kafka_service.lua`:

```lua
local log = require('log')
local json = require('json')
local repository = require('repository')

local connector = require('connector')

local function call(par)
    log.info("input: %s", json.encode(par))
    connector.send("to_kafka", par, {})
    return "ok"
end

local function processor(par)
    log.info("input: %s", json.encode(par))
    if next(par) and next(par.obj) and par.obj.id and par.obj.space_field_data then
        local data = {
            id = par.obj.id,
            space_field_data = par.obj.space_field_data
        }

        if par.obj.tokafka==true then
            connector.send("to_kafka", data, {})
        end
        if par.obj.tospace==true then
            local ok, err = repository.put('test_space', data)
            log.info("put answ: %s, err: %s", json.encode(ok), err)
        end
    else
        log.error("Broken data %s", json.encode(par.obj))
    end
    return true
end
return {
    call = call,
    processor = processor
}
```

### Обработчик <a name="lua-files2"></a>

Создайте файл `kafka_utils.lua`:

```lua
local connector = require('connector')

local function send_to_kafka(object, output_options)
    if not output_options then
        output_options = {}
    end
    connector.send("to_kafka", object, output_options)
end

return {
    send_to_kafka = send_to_kafka
}
```

## Загрузка конфигурации <a name="load-config"></a>

Чтобы загрузить файлы конфигурации в TDG, воспользуйтесь одним из способов ниже:

* В папке с примером находится скрипт `setconfig.py`. Чтобы загрузить конфигурацию, запустите этот скрипт, используя
следующую команду:

  ```
  cd /app
  python3 ./setconfig.py
  ```

* Создайте папку `src` и поместите в нее файл со скриптом обработчика (`kafka_service.lua`). Упакуйте файлы
`model.avsc`,`config.yml` и созданную папку `src` в архив формата ZIP. В веб-интерфейсе TDG перейдите на вкладку
`Configuration files`, нажмите на кнопку `Upload a new config` и загрузите архив.

Для экономии времени в примере для загрузки рекомендуется использовать скрипт `setconfig.py`.

# Установка и настройка Offset Explorer <a name="offset-exp-install"></a>

Чтобы облегчить работу с Kafka, установите приложение [Kafka Offset Explorer](https://www.kafkatool.com/download.html).
В приложении можно просматривать данные кластеров -- топики, брокеры, объекты и сообщения в топиках.
Offset Explorer позволяет проверить соединение с кластером Apache Kafka, так что при подозрении на ошибку попробуйте
подключиться к Kafka с его помощью. Если подключиться не удается, убедитесь, что конфигурация Kafka корректна.

Установив приложение, следуйте [инструкции](https://www.kafkatool.com/documentation/connecting.html) по подключению к
Kafka.

## Настройка Offset Explorer без SSL <a name="offset-exp-setup"></a>

В окне `Add Cluster` задайте настройки во вкладках `Properties` и `Advanced`:

1. Во вкладке `Properties` заполните поля с названием кластера и адресом Zookeeper:

    - Cluster name: `test`
    - Zookeeper Host: `localhost`
    - Zookeeper Port: `2181`

    Поля `Kafka Cluster Version` и `chroot path` оставьте без изменений.
2. Во вкладке `Advanced` для поля `Bootstrap servers` укажите номер порта, который используется для внешнего соединения.
   Задайте для поля значение `127.0.0.1:29092`.

## Настройка Offset Explorer с SSL <a name="offset-exp-setup-ssl"></a>

Перед добавлением кластера в Offset Explorer может понадобиться переконфигурировать jks-ключи:

```
cd /app/truststore
keytool -importkeystore -srckeystore ./kafka.truststore.jks -destkeystore kafka.jks -deststoretype jks
cd /app/keystore
keytool -importkeystore -srckeystore ./kafka-broker1.server.keystore.jks -destkeystore kafka-broker1.jks -deststoretype jks
```

После конфигурации в окне `Add Cluster` задайте настройки во вкладках `Properties`, `Security` и `Advanced`:

1. Во вкладке `Properties` заполните поля с названием кластера и адресом Zookeeper:

    - Cluster name: `test`
    - Zookeeper Host: `localhost`
    - Zookeeper Port: `2181`

    Поля `Kafka Cluster Version` и `chroot path` оставьте без изменений.
2. Во вкладке `Security` пропишите соответствующие ключи и пароли для них. 
3. Во вкладке `Advanced` для поля `Bootstrap servers` укажите номер порта, который используется для внешнего соединения.
   Задайте для поля значение `127.0.0.1:39092`.

# Работа в Offset Explorer <a name="offset-explorer"></a>

Перед началом работы проверьте, что Kafka работает через приложение Offset Explorer.
Чтобы проверить это, создайте в Offset Explorer следующие топики:
* `in.test.topic`
* `in.test.processor`
* `out.test.topic`

После загрузите рабочую конфигурацию для TDG:

```
cd /app
python3 ./setconfig.py
```

## Отправка сообщения в топик <a name="offset-exp-sendtotopic"></a>

Отправьте сообщение в топик `in.test.topic`:
```
echo "{\"test_space\":{\"id\":1,\"space_field_data\":\"test\"}}" |docker exec -i kafka-broker /opt/bitnami/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic in.test.topic
```
После отправки сообщения проверьте, что новая запись в спейсе `test_space` (`id = 1`, `space_field_data = test`) появилась 
* в Offset Explorer в топике `in.test.topic`;
* в веб-интерфейсе TDG. Чтобы проверить это, отправьте
во [вкладке Graphql](http://localhost:28080/admin/tdg/repl) в веб-интерфейсе следующий запрос:
    ```
    {test_space(pk:1){id,space_field_data}}
    ```

## Отправка сообщения напрямую в Kafka <a name="offset-exp-sendtokafka"></a>

Отправьте сообщение в Kafka, используя сервис `src/kafka_service.lua`. Для этого откройте
[вкладку Graphql](http://localhost:28080/admin/tdg/repl) в веб-интерфейсе и введите следующий запрос:
```
{sendkafka(input: "test")}
```
Сообщение должно появиться в приложении Offset Explorer в топике `in.test.topic`.

Далее проверьте сообщения, которые должны попадать в сервис `src/kafka_service.lua` в функцию `processor`. Для этого
выполните следующие действия:

1. Отправьте сообщение `tokafka = true`:
    ```
    echo "{\"id\":2,\"space_field_data\":\"test2\",\"tokafka\":true}" |docker exec -i kafka-broker /opt/bitnami/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic in.test.processor
    ``` 
2. Проверьте, что сообщение появилось в Kafka в топике `out.test.topic`
3. Отправьте сообщение `tokafka = tospaсe`
    ```
    echo "{\"id\":3,\"space_field_data\":\"test3\",\"tospaсe\":true}" |docker exec -i kafka-broker /opt/bitnami/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic in.test.processor
    ```
4. Проверьте, что сообщение появилось в спейсе в [веб-интерфейсе TDG](http://localhost:28080/admin/tdg/repl).
Для этого откройте вкладку Graphql и введите следующий запрос:

    ```
    {test_space(pk:3){id,space_field_data}}
    ```

# Воспроизведение ошибок <a name="troubleshooting"></a>

## Неверно указан брокер <a name="kafka-broker"></a>

Чтобы узнать больше об этой ошибке, обратитесь к [соответствующему разделу](https://www.tarantool.io/en/tdg/latest/development/kafka/troubleshoot-kafka/#troubleshoot-kafka-broker) в документации TDG.

**Как воспроизвести ошибку**

В файле конфигурации `config.yml` в input-коннекторе измените номер порта (`9092`) на другое значение - например, `9091`.

После изменения при запуске Kafka будет выведена ошибка:

```
Failed to resolve 'kafka-broker:9091': Name or service not known
```

**Как исправить ошибку**

1. Укажите корректный номер порта (`9092`). 
2. Почистите Docker-контейнеры:

    ```
    docker-compose stop
    docker-compose rm
    ```

3. Соберите заново чистые Docker-контейнеры:

    ```
    docker-compose up
    ```

4. Поднимите кластер по адресу `localhost:28080/admin`. Добавьте в кластере роли и сделайте `Bootstrap`.

## Несуществующий топик или раздел <a name="kafka-topic"></a>

Чтобы узнать больше об этой ошибке, обратитесь
к [соответствующему разделу](https://www.tarantool.io/en/tdg/latest/development/kafka/troubleshoot-kafka/#troubleshoot-kafka-unknown-topic)
в документации TDG.

**Как воспроизвести ошибку**

1. Подключитесь к Kafka c помощью Offset Explorer без SSL. 
2. Сразу после создания кластера, когда ошибок еще нет, список топиков в кластере будет пустой.
Чтобы воспроизвести ошибку, отправьте в топик сообщение, добавляющее новую запись в топик.
Отправьте новый кортеж в топик ``in.test.topic`` в спейс ``test_space``:

    ```
    echo "{\"test_space\":{\"id\":1,\"space_field_data\":\"test\}}" |docker exec -i kafka-broker /opt/bitnami/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic in.test.topiс
    ```
   
3. Если топика ``in.test.topic`` не существовало на момент отправки, возникнет ошибка о неизвестном топике.

**Как исправить ошибку**

Алгоритм решения проблемы указан в документации TDG в разделе
[Неизвестный топик или раздел](https://www.tarantool.io/en/tdg/latest/development/kafka/troubleshoot-kafka/#troubleshoot-kafka-unknown-topic).
При проверке разрешения на автоматическое создание топиков обратите внимание на следующие параметры:

*   ``allow.auto.create.topics`` в секции коннектора ``input`` в файле
    конфигурации ``config.yml``;

*   ``KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE`` в параметре брокера ``environment`` в файле конфигурации
    Docker-контейнеров (`docker-compose.yml`).
    Значение ``true``  для параметра разрешает автоматическое создание топиков.