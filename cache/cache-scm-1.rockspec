package = 'cache'
version = 'scm-1'
source  = {
    url = '/dev/null',
}
-- Put any modules your app depends on here
dependencies = {
    'tarantool',
    'lua >= 5.1',
    'luatest == 0.4.0-1',
    'cartridge == 2.0.0-1',
    'mysql'
}
build = {
    type = 'none';
}
