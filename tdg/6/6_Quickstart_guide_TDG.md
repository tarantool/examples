Пример №6 - Взаимодействие с Kafka

# Подготовка к работе

Для запуска примера используется виртуальная машина CentOS 7, поднятая c использованием Vagrant.

В примере описаны три контейнера, которые нужны для минимальной настройки подключения к Kafka, — Tarantool Data Grid,
[Zookeeper](https://zookeeper.apache.org/) и брокер (сервер) Kafka. Контейнеры развернуты с помощью 
[Docker Compose](https://docs.docker.com/compose/).

Пример можно использовать в качестве песочницы, если вы хотите воспроизвести в тестовом режиме ошибки, возникающие при
[взаимодействии с Kafka](https://www.tarantool.io/ru/tdg/latest/development/kafka/troubleshoot-kafka/).

## Установка и запуск Vagrant

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

## Подготовка и запуск Docker-контейнеров

### Настройка Docker-образа

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

Скачайте Docker-образ для TDG из AWS. Для этого:

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

### Генерация SSL-сертификатов и запуск Docker-контейнеров

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

После этого запустите остальные контейнеры:

```
docker-compose up -d
```

## Запуск и конфигурация TDG

Проверьте работоспособность TDG, открыв web-интерфейс по адресу
http://localhost:28080/admin/cluster/dashboard.

При входе в web-интерфейс TDG авторизация не требуется, поэтому
вы увидите главное окно с навигационным меню слева. По умолчанию открывается вкладка **Cluster**, где можно выполнить настройку
кластера (назначить роли и настроить репликацию, если они не были заданы в файле
конфигурации кластера при установке) для экземпляров кластера TDG. Подробнее о настройке кластера можно прочитать
в [соответствующем разделе](https://www.tarantool.io/ru/tdg/latest/administration/deployment/ansible-deployment/#ansible-deploy-topology) документации.

После выполнения первоначальной конфигурации кластера нажмите кнопку **Bootstrap vshard**
для инициализации распределённого хранилища данных.

Для завершения процесса запуска TDG в работу необходимо:
* задать доменную модель;
* загрузить конфигурацию и исполняемый код для обработки данных.

Все необходимые данные указываются в конфигурационном файле, включая ссылки на другие
файлы. Затем все необходимые файлы (конфигурационный файл и все упоминаемые в нём
файлы) и загружаются в TDG.
Далее приведено подробное описание процесса с указанием данных, используемых в примере.

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

### Исполняемые файлы

#### Обработчик

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

#### Обработчик

Создайте файл `kafka_utils.lua` со следующим содержимым:

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

В целях экономии времени в примере для загрузки рекомендуется использовать скрипт.

## Установка и настройка Offset Explorer

Чтобы облегчить работу с Kafka, установите приложение [Kafka Offset Explorer](https://www.kafkatool.com/download.html).
В приложении можно просматривать данные кластеров -- топики, брокеры, объекты и сообщения в топиках.
Offset Explorer позволяет проверить соединение с кластером Apache Kafka, так что при подозрении на ошибку попробуйте
подключиться к Kafka с его помощью.
Установив приложение, следуйте [инструкции](https://www.kafkatool.com/documentation/connecting.html) по подключению к
Kafka.

### Настройка Offset Explorer без SSL

В окне `Add Cluster` задайте настройки во вкладках `Properties` и `Advanced`:

1. Во вкладке `Properties` заполните поля с названием кластера и адресом Zookeeper:

    - Cluster name: `test`
    - Zookeeper Host: `localhost`
    - Zookeeper Port: `2181`

    Поля `Kafka Cluster Version` и `chroot path` оставьте без изменений.
2. Во вкладке `Advanced` для поля `Bootstrap servers` укажите номер порта, который используется для внешнего соединения.
   Задайте для поля значение `127.0.0.1:29092`.

### Настройка Offset Explorer с SSL

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

# Работа в Offset Explorer

Проверьте, что Kafka работает через приложение Offset Explorer.
Чтобы проверить это, создайте в Offset Explorer следующие топики:
1. `in.test.topic`
2. `in.test.processor`
3. `out.test.topic`

Примените рабочую конфигурацию для TDG:

```
cd /app/cont/configwork
python3 ./setconfig.py
```

Отправьте сообщение в топик `in.test.topic`:
```
echo "{\"test_space\":{\"id\":1,\"space_field_data\":\"test\"}}" |docker exec -i kafka-broker /opt/bitnami/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic in.test.topic
```

После отправки сообщения проверьте, что сообщение появилось
- в Offset Explorer в топике `in.test.topic`
- в спейсе (http://localhost:28080/admin/tdg/repl)
    ``` {test_space(pk:1){id,space_field_data}} ```

Далее отправьте напрямую сообщение в Kafka:

    http://localhost:28080/admin/tdg/repl
    ``` {sendkafka(input: "test")}```

Проверьте, что сообщение появилось в Offset Explorer в топике `in.test.topic`.

Проверьте сообщения, которые должны попадать в сервис `src/kafka_service.lua` -> `processor`. Для этого:
    - отправляем сообщение tokafka = true
    ```
    echo "{\"id\":2,\"space_field_data\":\"test2\",\"tokafka\":true}" |docker exec -i kafka-broker /opt/bitnami/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic in.test.processor
    ```
    - Проверяем что сообщение появилось в кафке в топике out.test.topik
    - отправляем сообщение tokafka = tospase
    ```
    echo "{\"id\":3,\"space_field_data\":\"test3\",\"tospase\":true}" |docker exec -i kafka-broker /opt/bitnami/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic in.test.processor
    ```
    - проверяем что сообщение появилось в спейсе
    http://localhost:28080/admin/tdg/repl
    ``` {test_space(pk:3){id,space_field_data}} ```

# Воспроизведение ошибок, связанных с Kafka

## Неверно указан брокер

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

## Несуществующий топик или раздел

**Как воспроизвести ошибку**

1. Подключитесь к Kafka c помощью Offset Explorer (без SSl). 
2. Сразу после создания кластера, когда ошибок еще нет, список топиков в кластере будет пустой.
Чтобы воспроизвести ошибку, отправьте в топик сообщение, добавляющее новую запись в топик.
Отправьте новый кортеж в топик ``in.test.topic`` в спейс ``test_space``:

    ```
    echo "{\"test_space\":{\"id\":1,\"space_field_data\":\"test\}}" |docker exec -i kafka-broker /opt/bitnami/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic in.test.topiс
    ```
   
3. Если топика ``in.test.topic`` не существовало на момент отправки, возникнет ошибка о неизвестном топике.



## Запуск чистого TDG

Разверните контейнер с TDG, используя Docker Compose:

  ```
  sudo su
  cd /app
  docker-compose up
  ```