CFCTime.ctime = CFCTime.ctime or {}

local ctime = CFCTime.ctime
local logger = CFCTime.Logger
local storage = CFCTime.Storage

local getNow = os.time

-- <steamID64> = { joined = <timestamp>, departed = <timestamp> | nil, duration = <float> }
ctime.pendingUpdates = {}
ctime.updateTimerName = "CFC_Time_UpdateTimer"
ctime.lastUpdate = getNow()

-- steamID65 = database session ID
ctime.sessions = {}

function ctime:updateTimes()
    local batch = {}
    local now = getNow()

    for steamId, data in pairs( self.pendingUpdates ) do
        local isValid = true

        local joined = data.joined
        local departed = data.departed
        local initialTime = data.initialTime

        if departed and departed < self.lastUpdate then
            self.pendingUpdates[steamId] = nil
            self.sessions[steamId] = nil
            isValid = false
        end

        local sessionTime = now - joined
        if sessionTime <= 0 then
            isValid = false
        end

        if isValid then
            local newTime = initialTime + sessionTime

            data.duration = newTime
            self.pendingUpdates[steamId].duration = newTime

            -- TODO: Find a better place to store the initial time so we don't have to do this
            data.initialTime = nil

            local sessionId = self.sessions[steamId]
            batch[sessionId] = data
        end
    end

    logger:debug( "Updating " .. table.Count( batch ) .. " sessions:" )

    storage:UpdateBatch( batch )
    ctime.lastUpdate = now
end

function ctime:startTimer()
    logger:debug( "Starting timer" )

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
    local now = getNow()
    local steamId = ply:SteamID64()

    storage:PlayerInit( steamId, now, function( data )
        local initialTime = data.totalTime
        local sessionId = data.sessionId

        ctime.sessions[steamId] = sessionId

        logger:debug( "Player " .. ply:GetName() .. " has initial time of " .. initialTime .. " at " .. now )

        self.pendingUpdates[steamId] = {
            joined = now,
            -- TODO: Find a better way to store initialTime
            initialTime = initialTime
        }

        hook.Run( "CFC_Time_PlayerInit", ply, initialTime, now )
    end )
end

function ctime:cleanupPlayer( ply )
    -- TODO: Verify bug report from the wiki: https://wiki.facepunch.com/gmod/GM:PlayerDisconnected
    local now = getNow()
    local steamId = ply:SteamID64()

    if not steamId then
        logger:error( "Player " .. ply:GetName() .. " did not have a steamID64 on disconnect" )
        return
    end

    logger:debug( "Player " .. ply:GetName() .. " ( " .. steamId .. " ) left at " .. now )

    self.pendingUpdates[steamId].departed = getNow()
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
