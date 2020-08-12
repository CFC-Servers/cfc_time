CFCTime.ctime = {}
local ctime = CFCTime.ctime

local function now()
    return os.time()
end

-- <steamID64> = { joined = <timestamp>, departed = <timestamp> | nil, initialTime = <float> }
ctime.pendingUpdates = {}
ctime.updateTimerName = "CFC_Time_UpdateTimer"
ctime.lastUpdate = now()

function ctime:updateTimes()
    local batch = {}
    local now = now()

    for steamId, data in pairs( self.pendingUpdates ) do
        local isValid = true
        local joined = data.joined
        local departed = data.departed
        local initialTime = data.initialTime

        if departed < self.lastUpdate then
            self.pendingUpdates[steamId] = nil
            isValid = false
        end

        if isValid then
            local sessionTime = now - joined
            local newTime = initialTime + sessionTime

            batch[steamId] = newTime
        end
    end

    CFCTime.SQL:UpdateTimeBatch( batch )
    ctime.lastUpdate = now
end

function ctime:startTimer()
    timer.Create(
        self.updateTimerName,
        self.Config.updateInterval,
        0,
        function() ctime:updateTimes() end
    )
end

function ctime:stopTimer()
    timer.Remove( self.updateTimerName )
end

function ctime:initPlayer( ply )
    local now = now()
    local steamId = ply:SteamID64()
    local initialTime = CFCTime.SQL:getTime( steamId )

    self.pendingUpdates[steamId] = {
        joined = now,
        initialTime = initialTime
    }
end

function ctime:cleanupPlayer( ply )
    -- TODO: Verify bug report from the wiki: https://wiki.facepunch.com/gmod/GM:PlayerDisconnected
    local steamId = ply:SteamID64()
    self.pendingUpdates[steamId].departed = now()
end

hook.Add( "Think", "CFC_Time_Init", function()
    ctime:startTimer()
    hook.Remove( "Think", "CFC_Time_Init" )
end )

hook.Add( "PlayerFullLoad", "CFC_Time_PlayerInit", function( ply )
    ctime:initPlayer( ply )
end )

hook.Add( "PlayerDisconnected", "CFC_Time_PlayerCleanup", function( ply )
    ctime:cleanupPlayer( ply )
end )
