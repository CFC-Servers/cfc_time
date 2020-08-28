-- We create a mock Utime so addons that require it think we have it
Utime = {}

-- Addons like APromote rely on the utime_welcome convar existing for some reason?
CreateConVar( "utime_welcome", "1", FCVAR_ARCHIVE )

local logger = CFCTime.Logger
local plyMeta = FindMetaTable( "Player" )

function plyMeta:GetUTime()
    return self:GetNWFloat( "CFC_Time_TotalTime", 0 )
end

function plyMeta:GetUTimeStart()
    return self:GetNWFloat( "CFC_Time_SessionStart", 0 )
end

function plyMeta:GetUTimeSessionTime()
    return self:GetNWFloat( "CFC_Time_SessionDuration", 0 )
end

function plyMeta:GetUTimeTotalTime()
    local total = self:GetNWFloat( "CFC_Time_TotalTime", 0 )
    local session = self:GetNWFloat( "CFC_Time_SessionDuration", 0 )

    return total - session
end

if SERVER then
    CFCTime.utimeCompatability = {}
    local compat = CFCTime.utimeCompatability

    function compat:MigratePlayerFromUtime( ply )
        local steamID = ply:SteamID64()
        local uniqueId = ply:UniqueID()

        local utimeQuery = "SELECT totaltime, lastvisit FROM utime WHERE player = " .. uniqueId
        local utimeData = sql.QueryRow( utimeQuery )

        if not utimeData then return end

        local totalTime, lastVisit = utimeData.totaltime, utimeData.lastvisit

        local sessionStart = lastVisit - totalTime
        local sessionEnd = lastVisit

        CFCTime.Storage:CreateSession( nil, steamID, sessionStart, sessionEnd, totalTime )

        CFCTime.Logger:info( "Player " .. ply:GetName() .. "[" .. steamID .. "] migrated from UTime with existing time of " .. totalTime )

        return totalTime
    end

    hook.Add( "CFC_Time_PlayerInitialTime", "CFC_Time_UtimeCompat", function( ply, firstVisit, timeStruct )
        if not firstVisit then return end

        logger:debug( "[UtimeCompat] Received PlayerInitialTime hook for first-time player - migrating time!")

        local totalUtime = compat:MigratePlayerFromUtime( ply )
        timeStruct:add( totalUtime )
    end )

    hook.Add( "CFC_Time_PlayerTimeUpdated", "CFC_Time_UtimeCompat", function( ply, totalTime, joined )
        ply:SetNWFloat( "TotalUTime", totalTime )
        ply:SetNWFloat( "UTimeStart", joined )
    end )
end
