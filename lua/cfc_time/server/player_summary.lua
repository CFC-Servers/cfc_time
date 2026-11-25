util.AddNetworkString( "CFC_Time_PlayerSummary" )

local storage = CFCTime.Storage

local function canRequestPlayerSummary( ply )
    local hookResult = hook.Run( "CFC_Time_CanRequestPlayerSummary", ply )
    if hookResult ~= nil then return hookResult end

    return ply:IsAdmin()
end

net.Receive( "CFC_Time_PlayerSummary", function( _, ply )
    if not canRequestPlayerSummary( ply ) then return end

    local steamID64 = net.ReadString()

    storage:GetPlayerSummary( steamID64, function( summary )
        if not IsValid( ply ) then return end

        net.Start( "CFC_Time_PlayerSummary" )
        net.WriteString( steamID64 )
        net.WriteUInt( summary.firstJoin, 32 )
        net.WriteUInt( summary.lastJoin, 32 )
        net.WriteUInt( summary.totalTime, 32 )
        net.Send( ply )
    end )
end )
