CFCTime.ctime = CFCTime.ctime or {}

local ctime = CFCTime.ctime
local logger = CFCTime.Logger
local storage = CFCTime.Storage

local getNow = os.time

-- <steamID64> = { joined = <timestamp>, departed = <timestamp> | nil, duration = <float> }
ctime.sessions = {}
ctime.updateTimerName = "CFC_Time_UpdateTimer"

-- <steamID64> = <timestamp of last update for given player>
ctime.lastUpdateTime = {}

-- steamID64 = <database session ID>
ctime.sessionIDs = {}

-- steamID64 = <total time float>
-- purely cosmetic, does not affect times in the database
ctime.totalTimes = {}

-- steamID64 = <player entity>
local steamIDToPly = {}

function ctime:untrackPlayer( steamID )
    self.sessions[steamID] = nil
    self.sessionIDs[steamID] = nil
    self.totalTimes[steamID] = nil
    self.lastUpdateTime[steamID] = nil
    steamIDToPly[steamID] = nil
end

function ctime:broadcastPlayerTime( ply, totalTime, joined, duration )
    ply:SetNWFloat( "CFC_Time_TotalTime", totalTime )
    ply:SetNWFloat( "CFC_Time_SessionStart", joined )
    ply:SetNWFloat( "CFC_Time_SessionDuration", duration )

    hook.Run( "CFC_Time_PlayerTimeUpdated", ply, totalTime, joined, duration )
end

function ctime:broadcastTimes( only )
    local times = self.totalTimes

    if only then
        times = { [only] = times[only] }
    end

    for steamID, totalTime in pairs( times ) do
        local ply = steamIDToPly[steamID]

        local session = self.sessions[steamID]

        local joined = session.joined
        local duration = session.duration

        self:broadcastPlayerTime( ply, totalTime, joined, duration )
    end
end

function ctime:updateTimes( only )
    local batch = {}
    local now = getNow()
    local sessions = self.sessions

    if only then
        logger:debug( "Running updateTimes for only: " .. only )
        sessions = { [only] = sessions[only] }
    end

    for steamID, data in pairs( sessions ) do
        local isValid = true
        local joined = data.joined
        local departed = data.departed

        local lastUpdate = self.lastUpdateTime[steamID]
        local timeDelta = now - lastUpdate

        local sessionTime = ( departed or now ) - joined
        if sessionTime <= 0 then
            isValid = false
        end

        if isValid then
            local sessionID = self.sessionIDs[steamID]
            local newTotal = self.totalTimes[steamID] + timeDelta

            local shouldUpdate = hook.Run( "CFC_Time_UpdatePlayerTime", steamID, timeDelta, newTotal )

            if shouldUpdate == false then
                logger:debug(
                    string.format(
                        "Ignoring player time update (%s) because something returned false on the update hook",
                        steamID
                    )
                )
            else
                data.duration = sessionTime
                batch[sessionID] = data
                self.totalTimes[steamID] = newTotal
            end
        end

        self.lastUpdateTime[steamID] = now

        if departed then
            self:untrackPlayer( steamID )
        end
    end

    if table.IsEmpty( batch ) then return end

    logger:debug( "Updating " .. table.Count( batch ) .. " sessions:" )
    logger:debug( batch )

    storage:UpdateBatch( batch )
    self:broadcastTimes( only )
end

function ctime:startTimer()
    logger:debug( "Starting timer" )

    local function timeUpdater()
        local success, err = pcall( function() ctime:updateTimes() end )

        if not success then
            logger:fatal( "Update times call failed with an error!", err )
        end
    end

    timer.Create(
        self.updateTimerName,
        CFCTime.Config.get( "UPDATE_INTERVAL" ),
        0,
        timeUpdater
    )
end

function ctime:initPlayer( ply )
    local now = getNow()
    local steamID = ply:SteamID64()

    local function setupPly( totalTime, isFirstVisit )
        local sessionTotalTime = totalTime + ( getNow() - now )

        local initialTime = { seconds = 0 }

        initialTime.add = function( seconds )
            initialTime.seconds = initialTime.seconds + seconds
        end

        initialTime.set = function( seconds )
            initialTime.seconds = seconds
        end

        hook.Run( "CFC_Time_PlayerInitialTime", ply, isFirstVisit, initialTime )
        sessionTotalTime = sessionTotalTime + initialTime.seconds

        ctime.totalTimes[steamID] = sessionTotalTime
        ctime:updateTimes( steamID )
    end

    storage:PlayerInit( ply, now, function( data )
        local isFirstVisit = data.isFirstVisit
        local sessionID = data.sessionID

        steamIDToPly[steamID] = ply
        ctime.sessionIDs[steamID] = sessionID
        ctime.sessions[steamID] = { joined = now }
        ctime.lastUpdateTime[steamID] = now

        if isFirstVisit then return setupPly( 0, true ) end

        storage:GetTotalTime( steamID, function( total )
            setupPly( total, false )
        end )
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

    logger:debug(
        string.format(
            "Player %s ( %s ) left at %d",
            ply:GetName(),
            steamID,
            now
        )
    )

    if not self.sessions[steamID] then
        logger:error( "No pending update for above player, did they leave before database returned?" )
        return
    end

    self.sessions[steamID].departed = now
    self:updateTimes( steamID )
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
