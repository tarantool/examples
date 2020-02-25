FROM artembo/cartridge:latest


COPY . /opt/tarantool/cache
WORKDIR /opt/tarantool/cache
RUN tarantoolctl rocks install luatest
RUN ln -s /opt/tarantool/cache/.rocks/bin/luatest /usr/local/bin/luatest
RUN chmod +x init.lua
RUN yum install openssl-devel -y
RUN tarantoolctl rocks install mysql
RUN tarantoolctl rocks install http

CMD bash run-tests.sh
