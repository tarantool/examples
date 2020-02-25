FROM artembo/cartridge:latest


COPY . /opt/tarantool/cache
WORKDIR /opt/tarantool/cache
RUN tarantoolctl rocks install luatest && \
    ln -s /opt/tarantool/cache/.rocks/bin/luatest /usr/local/bin/luatest && \
    chmod +x * && \
    yum install openssl-devel -y && \
    tarantoolctl rocks install mysql && \
    tarantoolctl rocks install http

CMD luatest
