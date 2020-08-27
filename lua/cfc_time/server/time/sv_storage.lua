CFCTime.Storage = {}

--include( "sv_mysql.lua" )

CFCTime.Storage.realm = "cfctest"
include( "sv_mysql.lua" )

-- if mysql, load sv_mysql.lua
-- else/if mysqlite load sv_sqlite.lua
