
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
    return CurTime() - self:GetUTimeStart()
end

function plyMeta:GetUTimeTotalTime()
    return self:GetUTime() + CurTime() - self:GetUTimeStart()
end

if SERVER then
    CFCTime.utimeCompat = {}
    
    -- TODO: When does this happen? How do we handle a situation where this happens before the player has been created in our storage?
    function CFCTime.utimeCompat:MigratePlayerFromUtime( ply )
        local steamId = ply:SteamID64()
        local uniqueId = ply:UniqueID()

        local utimeQuery = "SELECT totaltime, lastvisit FROM utime WHERE player = " .. uniqueId
        local utimeData = sql.QueryRow( utimeQuery )

        if not utimeData then return end

        local totaltime, lastvisit = utimeData.totaltime, utimeData.lastvisit

        local sessionStart = lastvisit - totaltime
        local sessionEnd = lastvisit

        CFCTime.Storage:CreateSession( nil, steamId, sessionStart, sessionEnd, totaltime)
    end

    hook.Add( "CFC_Time_PlayerInit", "CFC_Time_UtimeCompat", function( ply, initialTime, currentTime )
        CFCTime.utimeCompat:MigratePlayerFromUtime( ply )

        ply:SetUTime( initialTime )
        ply:SetUTimeStart( currentTime )
    end )
end
