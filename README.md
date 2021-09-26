# cfc_time
A drop-in replacement for Utime with multiple storage options, greater customization, and an emphasis on quality + performance.

## Dependencies
- [CFCLogger](https://github.com/CFC-Servers/cfc_logger)
- [PlayerFullLoad](https://github.com/CFC-Servers/gm_playerload)

## Using Mysql
- Ensure your mysql server has ssl disabled
- If you run into an error involving `caching_sha2_password` you can try disabling that for the mysql user `ALTER USER 'yourusername' IDENTIFIED WITH mysql_native_password BY 'youpassword';`
- Install mysqloo
- Run: `cfc_time_config_set "STORAGE_TYPE" "mysql"` in the server console
- Restart the server
- Run the following commands in the server console with the values changed to your database credentials
    `cfc_time_config_set "MYSQL_HOST" "127.0.0.1"`
    `cfc_time_config_set "MYSQL_USERNAME" "username"`
    `cfc_time_config_set "MYSQL_PASSWORD" "password"`
    `cfc_time_config_set "MYSQL_DATABASE" "database"`
    `cfc_time_config_set "MYSQL_PORT" "3306"`
- Restart Server
