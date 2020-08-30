CFCTime.Storage = {}

local storageType = CFCTime.Config.get( "STORAGE_TYPE" )

CFCTime.Storage.realm = CFCTime.Config.get( "REALM" )

include( "storage_options/" .. storageType .. ".lua" )
