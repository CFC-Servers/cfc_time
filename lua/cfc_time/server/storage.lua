CFCTime.Storage = {}

local storageType = CFCTime.Config.get( "STORAGE_TYPE" )

CFCTime.Storage.realm = CFCTime.Config.get( "REALM" )

function CFCTime.Storage:BuildPlayerSummary( row )
    local firstJoin = tonumber( row.first_join )
    if not firstJoin then return nil end

    return {
        firstJoin = firstJoin,
        lastJoin = tonumber( row.last_join ),
        totalTime = tonumber( row.total_time )
    }
end

include( "storage_options/" .. storageType .. ".lua" )
