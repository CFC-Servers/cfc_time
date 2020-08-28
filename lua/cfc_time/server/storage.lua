CFCTime.Storage = {}

local storageType = CFCTime.Config.get( "storageType" )

CFCTime.Storage.realm = CFCTime.Config.get( "realm" )

include( "storage_options/" .. storageType .. ".lua" )
