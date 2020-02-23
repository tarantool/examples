FROM tarantool/cartridge:2


RUN tarantoolctl rocks install luatest

COPY cache /opt/tarantool/cache
COPY profile-storage /opt/tarantool/profile-storage
