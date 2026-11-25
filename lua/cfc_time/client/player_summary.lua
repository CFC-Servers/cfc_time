local pendingCallbacks = {}

local function readSummary()
    local hasSessions = net.ReadBool()
    if not hasSessions then return nil end

    return {
        firstJoin = net.ReadUInt( 32 ),
        lastJoin = net.ReadUInt( 32 ),
        totalTime = net.ReadUInt( 32 )
    }
end

function CFCTime.RequestPlayerSummary( steamID64, callback )
    pendingCallbacks[steamID64] = callback

    net.Start( "CFC_Time_PlayerSummary" )
    net.WriteString( steamID64 )
    net.SendToServer()
end

net.Receive( "CFC_Time_PlayerSummary", function()
    local steamID64 = net.ReadString()
    local summary = readSummary()

    local callback = pendingCallbacks[steamID64]
    if not callback then return end

    pendingCallbacks[steamID64] = nil
    callback( summary )
end )
