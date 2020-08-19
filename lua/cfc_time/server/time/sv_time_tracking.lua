CFCTime.ctime = CFCTime.ctime or {}
local ctime = CFCTime.ctime

local now = os.time

-- <steamID64> = { joined = <timestamp>, departed = <timestamp> | nil, initialTime = <float> }
ctime.pendingUpdates = {}
ctime.updateTimerName = "CFC_Time_UpdateTimer"
ctime.lastUpdate = now()

-- steamID65 = database session ID
ctime.sessions = {}

function ctime:updateTimes()
    local batch = {}
    local now = now()

    for steamId, data in pairs( self.pendingUpdates ) do
        local isValid = true
        local joined = data.joined
        local departed = data.departed
        local initialTime = data.initialTime

        if departed and departed < self.lastUpdate then
            self.pendingUpdates[steamId] = nil
            isValid = false
        end

        local sessionTime = now - joined
        if sessionTime <= 0 then
            isValid = false
        end

        if isValid then
            local newTime = initialTime + sessionTime

            batch[steamId] = newTime
        end
    end

    CFCTime.logger:debug( "Updating " .. table.Count( batch ) .. " times:" )

    CFCTime.SQL:UpdateTimeBatch( batch )
    ctime.lastUpdate = now
end

function ctime:startTimer()
    CFCTime.logger:debug( "Starting timer" )

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

    CFCTime.logger:debug( "Player " .. ply:GetName() .. " has initial time of " .. initialTime .. " at " .. now )

    self.pendingUpdates[steamId] = {
        joined = now,
        initialTime = initialTime
    }

    hook.Run( "CFC_Time_PlayerInit", ply, initialTime, now )
end

function ctime:cleanupPlayer( ply )
    -- TODO: Verify bug report from the wiki: https://wiki.facepunch.com/gmod/GM:PlayerDisconnected
    local now = now()
    local steamId = ply:SteamID64()

    if not steamId then
        CFCTime.logger:error( "Player " .. ply:GetName() .. " did not have a steamID64 on disconnect" )
        return
    end

    CFCTime.logger:debug( "Player " .. ply:GetName() .. " ( " .. steamId .. " ) left at " .. now )

    self.pendingUpdates[steamId].departed = now()
end

hook.Add( "Think", "CFC_Time_Init", function()
    hook.Remove( "Think", "CFC_Time_Init" )
    ctime:startTimer()
end )

hook.Add( "PlayerFullLoad", "CFC_Time_PlayerInit", function( ply )
    ctime:initPlayer( ply )
end )

hook.Add( "PlayerDisconnected", "CFC_Time_PlayerCleanup", function( ply )
    ctime:cleanupPlayer( ply )
end )
