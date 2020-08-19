-- Load the sv_init.lua from all subfolders, or the files directly if they're alone

include( "glua-mysql-wrapper/mysql.lua" )
CFCTime.includeModules( "server", "sv_init.lua" )
