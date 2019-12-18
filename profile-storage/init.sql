CREATE DATABASE IF NOT EXISTS profile_storage;
USE profile_storage;
CREATE TABLE IF NOT EXISTS user_profile (
    profile_id integer unsigned primary key,
    bucket_id integer unsigned,
    first_name varchar(20),
    second_name varchar(20),
    patronymic varchar(20),
    msgs_count integer unsigned,
    service_info varchar(20)
);