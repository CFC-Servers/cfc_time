CFCTime.Storage = {}

local storageType = CFCTime.Config.get( "storageType" )

<<<<<<< HEAD:lua/cfc_time/server/storage.lua
CFCTime.Storage.realm = "cfctest"
include( "storage_options/sqlite.lua" )
=======
CFCTime.Storage.realm =  CFCTime.Config.get( "realm" )
>>>>>>> master:lua/cfc_time/server/time/sv_storage.lua

include( "storage_options/"..storageType..".lua" )
