util.AddNetworkString( "CFC_Time_PlayerSummary" )

local storage = CFCTime.Storage

local STEAMID64_PATTERN = "^7656119%d%d%d%d%d%d%d%d%d%d$"

local function sendSummary( ply, steamID64, summary )
    if not IsValid( ply ) then return end

    local hasSessions = summary ~= nil

    net.Start( "CFC_Time_PlayerSummary" )
    net.WriteString( steamID64 )
    net.WriteBool( hasSessions )

    if hasSessions then
        net.WriteUInt( summary.firstJoin, 32 )
        net.WriteUInt( summary.lastJoin, 32 )
        net.WriteUInt( summary.totalTime, 32 )
    end

    net.Send( ply )
end

net.Receive( "CFC_Time_PlayerSummary", function( _, ply )
    if not ply:IsAdmin() then return end

    local steamID64 = net.ReadString()
    if not string.match( steamID64, STEAMID64_PATTERN ) then return end

    storage:GetPlayerSummary( steamID64, function( summary )
        sendSummary( ply, steamID64, summary )
    end )
end )
