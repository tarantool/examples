-- Модуль проверки аргументов в функции
local checks = require('checks')
-- Модуль с криптографическими функциями
local digest = require('digest')

local SALT_LENGTH = 16

local function generate_salt(length)
    return digest.base64_encode(
        digest.urandom(length - bit.rshift(length, 2)),
        {nopad=true, nowrap=true}
    ):sub(1, length)
end

local function password_digest(password, salt)
    checks('string', 'string')
    return digest.pbkdf2(password, salt)
end

local function create_password(password)
    checks('string')

    local salt = generate_salt(SALT_LENGTH)

    local shadow = password_digest(password, salt)

    return {
        shadow = shadow,
        salt = salt,
    }
end

local function check_password(profile, password)
    return profile.shadow == password_digest(password, profile.salt)
end

return {
    create_password = create_password,
    check_password = check_password
}