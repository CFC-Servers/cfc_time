local pendingCallbacks = {}

function CFCTime.RequestPlayerSummary( steamID64, callback )
    local callbacks = pendingCallbacks[steamID64]
    if callbacks then
        table.insert( callbacks, callback )
        return
    end

    pendingCallbacks[steamID64] = { callback }

    net.Start( "CFC_Time_PlayerSummary" )
    net.WriteString( steamID64 )
    net.SendToServer()
end

net.Receive( "CFC_Time_PlayerSummary", function()
    local steamID64 = net.ReadString()
    local firstJoin = net.ReadUInt( 32 )
    local lastJoin = net.ReadUInt( 32 )
    local totalTime = net.ReadUInt( 32 )

    local callbacks = pendingCallbacks[steamID64]
    if not callbacks then return end

    pendingCallbacks[steamID64] = nil

    for _, callback in ipairs( callbacks ) do
        callback( firstJoin, lastJoin, totalTime )
    end
end )
