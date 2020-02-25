FROM tarantool/cartridge:2


RUN tarantoolctl rocks install luatest
RUN ln -s /opt/tarantool/.rocks/bin/luatest /usr/local/bin/luatest


COPY . /opt/tarantool/profile-storage
WORKDIR /opt/tarantool/profile-storage

CMD luatest
