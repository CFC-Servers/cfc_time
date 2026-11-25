CFCTime.Storage = {}

local storageType = CFCTime.Config.get( "STORAGE_TYPE" )

CFCTime.Storage.realm = CFCTime.Config.get( "REALM" )

function CFCTime.Storage:BuildPlayerSummary( row )
    return {
        firstJoin = tonumber( row.first_join ) or 0,
        lastJoin = tonumber( row.last_join ) or 0,
        totalTime = tonumber( row.total_time ) or 0
    }
end

include( "storage_options/" .. storageType .. ".lua" )
