local pendingCallbacks = {}

function CFCTime.RequestPlayerSummary( steamID64, callback )
    pendingCallbacks[steamID64] = callback

    net.Start( "CFC_Time_PlayerSummary" )
    net.WriteString( steamID64 )
    net.SendToServer()
end

net.Receive( "CFC_Time_PlayerSummary", function()
    local steamID64 = net.ReadString()
    local firstJoin = net.ReadUInt( 32 )
    local lastJoin = net.ReadUInt( 32 )
    local totalTime = net.ReadUInt( 32 )

    local callback = pendingCallbacks[steamID64]
    if not callback then return end

    pendingCallbacks[steamID64] = nil
    callback( firstJoin, lastJoin, totalTime )
end )
