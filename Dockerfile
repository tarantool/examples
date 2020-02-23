FROM tarantool/cartridge:2

RUN tarantoolctl rocks install luarocks
RUN ln -s /opt/tarantool/.rocks/bin /usr/bin/local/luatest

COPY cache /opt/tarantool/cache
COPY profile-storage /opt/tarantool/cache/profile-storage

#CMD cd /opt/tarantool/cache && luatest; cd /opt/tarantool/profile-storage && luatest