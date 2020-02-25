#!/usr/bin/env bash

set -e

luatest ./test/unit
luatest ./test/integration/cache_mysql_test.lua
luatest ./test/integration/cache_vinyl_test.lua
luatest ./test/integration/simple_cache_test.lua
luatest ./test/integration/api_test.lua
