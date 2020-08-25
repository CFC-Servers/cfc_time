CFCTime.ctime = CFCTime.ctime or {}

local ctime = CFCTime.ctime
local logger = CFCTime.Logger
local storage = CFCTime.Storage

local getNow = os.time

-- <database session ID> = { joined = <timestamp>, departed = <timestamp> | nil, duration = <float> }
ctime.pendingUpdates = {}
ctime.updateTimerName = "CFC_Time_UpdateTimer"
ctime.lastUpdate = getNow()

-- steamID64 = <database session ID>
ctime.sessions = {}

-- steamID64 = <total time float>
ctime.totalTimes = {}

-- steamID64 = <player entity>
local steamIDToPly = {}

function ctime:broadcastPlayerTime( ply, totalTime, joined, duration )
    ply:SetNWFloat( "CFC_Time_TotalTime", totalTime )
    ply:SetNWFloat( "CFC_Time_SessionStart", joined )
    ply:SetNWFloat( "CFC_Time_SessionDuration", duration )

    hook.Run( "CFC_Time_PlayerTimeUpdated", ply, totalTime, joined, duration )
end

function ctime:broadcastTimes( sessions )
    for steamID, totalTime in pairs( self.totalTimes ) do
        local ply = steamIDToPly[steamID]

        -- TODO: These tables seem like they have a weird name when used in this context
        -- Maybe self.pendingUpdates becomes self.sessions
        -- And self.sessions becomes self.sessionIDs
        local sessionID = self.sessions[steamID]
        local session = self.pendingUpdates[sessionID]

        local joined = session.joined
        local duration = session.duration

        self:broadcastPlayerTime( ply, totalTime, joined, duration )
    end
end

function ctime:updateTimes()
    local batch = {}
    local now = getNow()

    for steamID, data in pairs( self.pendingUpdates ) do
        local isValid = true

        local joined = data.joined
        local departed = data.departed

        if departed and departed < self.lastUpdate then
            self.pendingUpdates[steamID] = nil
            self.sessions[steamID] = nil
            self.totalTimes[steamID] = nil
            steamIDToPly[steamID] = nil
            isValid = false
        end

        local sessionTime = ( departed or now ) - joined
        if sessionTime <= 0 then
            isValid = false
        end

        if isValid then
            data.duration = sessionTime

            local sessionID = self.sessions[steamID]
            batch[sessionID] = data

            local timeDelta = now - self.lastUpdate
            local newTotal = self.totalTimes[steamID] + timeDelta
            self.totalTimes[steamID] = newTotal
        end
    end

    if table.IsEmpty( batch ) then return end

    logger:debug( "Updating " .. batchCount .. " sessions:" )
    logger:debug( batch )

    storage:UpdateBatch( batch )
    self:broadcastTimes()
    self.lastUpdate = now
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
    local steamID = ply:SteamID64()

    storage:PlayerInit( ply, now, function( data )
        local totalTime = data.totalTime
        local sessionID = data.sessionID

        ctime.sessions[steamID] = sessionID
        ctime.totalTimes[steamID] = totalTime
        steamIDToPly[steamID] = ply

        logger:debug( "Player " .. ply:GetName() .. " has a total time of " .. tostring( totalTime ) .. " at " .. now )

        self.pendingUpdates[steamID] = {
            joined = now
        }

        ctime:broadcastPlayerTime( ply, totalTime, now, 0 )
    end )
end

function ctime:cleanupPlayer( ply )
    -- TODO: Verify bug report from the wiki: https://wiki.facepunch.com/gmod/GM:PlayerDisconnected
    local now = getNow()
    local steamID = ply:SteamID64()

    if not steamID then
        logger:error( "Player " .. ply:GetName() .. " did not have a steamID64 on disconnect" )
        return
    end

    logger:debug( "Player " .. ply:GetName() .. " ( " .. steamID .. " ) left at " .. now )

    if not self.pendingUpdates[steamID] then
        logger:error( "No pending update for above player, did they leave before database returned?" )
        return
    end

    self.pendingUpdates[steamID].departed = getNow()
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
