local plyMeta = FindMetaTable( "Player" )

function plyMeta:GetUTime()
    return self:GetNWFloat( "CFC_Time_TotalTime" )
end

function plyMeta:GetUTimeStart()
    return self:GetNWFloat( "CFC_Time_SessionStart" )
end

function plyMeta:GetUTimeSessionTime()
    return self:GetNWFloat( "CFC_Time_SessionDuration" )
end

function plyMeta:GetUTimeTotalTime()
    local total = self:GetNWFloat( "CFC_Time_TotalTime" )
    local session = self:GetNWFloat( "CFC_Time_SessionDuration" )

    return total - session
end

if SERVER then
    CFCTime.utimeCompat = {}
    compatability = CFCTime.utimeCompat

    function compatability:MigratePlayerFromUtime( ply )
        local steamId = ply:SteamID64()
        local uniqueId = ply:UniqueID()

        local utimeQuery = "SELECT totaltime, lastvisit FROM utime WHERE player = " .. uniqueId
        local utimeData = sql.QueryRow( utimeQuery )

        if not utimeData then return end

        local totalTime, lastVisit = utimeData.totaltime, utimeData.lastvisit

        local sessionStart = lastVisit - totalTime
        local sessionEnd = lastVisit

        CFCTime.Storage:CreateSession( nil, steamId, sessionStart, sessionEnd, totalTime )

        CFCTime.Logger:info( "Player " .. ply:GetName() .. "[" .. steamId .. "] migrated from UTime with existing time of " .. totalTime )

        return totalTime
    end

    hook.Add( "CFC_Time_NewPlayer", "CFC_Time_UtimeCompat", function( ply )
        compatability:MigratePlayerFromUtime( ply )
    end )

    hook.Add( "CFC_Time_PlayerTimeUpdated", "CFC_Time_UtimeCompat", function( ply, totalTime, joined )
        ply:SetNWFloat( "TotalUTime", totalTime )
        ply:SetNWFloat( "UTimeStart", joined )
    end )
end
