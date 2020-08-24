local plyMeta = FindMetaTable( "Player" )

function plyMeta:GetUTime()
    return self:GetNWFloat( "TotalUTime" )
end

function plyMeta:SetUTime( time )
    self:SetNWFloat( "TotalUTime", time )
end

function plyMeta:GetUTimeStart()
    return self:GetNWFloat( "UTimeStart" )
end

function plyMeta:SetUTimeStart( time )
    self:SetNWFloat( "UTimeStart", time )
end

function plyMeta:GetUTimeSessionTime()
    return os.time() - self:GetUTimeStart()
end

function plyMeta:GetUTimeTotalTime()
    return self:GetUTime() + os.time() - self:GetUTimeStart()
end

if SERVER then
    CFCTime.utimeCompat = {}

    function CFCTime.utimeCompat:MigratePlayerFromUtime( ply )
        local steamId = ply:SteamID64()
        local uniqueId = ply:UniqueID()

        local utimeQuery = "SELECT totaltime, lastvisit FROM utime WHERE player = " .. uniqueId
        local utimeData = sql.QueryRow( utimeQuery )

        if not utimeData then return end

        local totaltime, lastvisit = utimeData.totaltime, utimeData.lastvisit

        local sessionStart = lastvisit - totaltime
        local sessionEnd = lastvisit

        CFCTime.Storage:CreateSession( nil, steamId, sessionStart, sessionEnd, totaltime )

        CFCTime.Logger:info( "Player " .. ply:GetName() .. "[" .. steamId .. "] migrated from UTime with existing time of " .. totalTime )

        return totalTime
    end

    hook.Add( "CFC_Time_NewPlayer", "CFC_Time_UtimeCompat", function( ply )
        return CFCTime.utimeCompat:MigratePlayerFromUtime( ply )
    end )

    hook.Add( "CFC_Time_PlayerInit", "CFC_Time_UtimeCompat", function( ply, initialTime, currentTime )
        ply:SetUTime( initialTime )
        ply:SetUTimeStart( currentTime )
    end )
end
