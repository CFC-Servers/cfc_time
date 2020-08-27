CFCTime.Storage = {}

--include( "sv_mysql.lua" )

CFCTime.Storage.realm = "cfctest"
include( "storage_options/sqlite.lua" )

-- if mysql, load sv_mysql.lua
-- else/if mysqlite load sv_sqlite.lua
