CFCTime.ctime = CFCTime.ctime or {}

local ctime = CFCTime.ctime
local logger = CFCTime.Logger:scope( "Tracking" )
local storage = CFCTime.Storage

local getNow = os.time

-- <steamID64> = { joined = <timestamp>, departed = <timestamp> | nil, duration = <float> }
ctime.sessions = {}
ctime.updateTimerName = "CFC_Time_UpdateTimer"
ctime.lastUpdate = getNow()

-- steamID64 = <database session ID>
ctime.sessionIDs = {}

-- steamID64 = <total time float>
-- purely cosmetic, does not affect times in the database
ctime.totalTimes = {}

-- steamID64 = <player entity>
local steamID64ToPly = {}

function ctime:broadcastPlayerTime( ply, totalTime, joined, duration )
    ply:SetNW2Float( "CFC_Time_TotalTime", totalTime )
    ply:SetNW2Float( "CFC_Time_SessionStart", joined )
    ply:SetNW2Float( "CFC_Time_SessionDuration", duration )

    hook.Run( "CFC_Time_PlayerTimeUpdated", ply, totalTime, joined, duration )
end

function ctime:broadcastTimes()
    for steamID64, totalTime in pairs( self.totalTimes ) do
        local ply = steamID64ToPly[steamID64]

        local session = self.sessions[steamID64]

        local joined = session.joined
        local duration = session.duration

        self:broadcastPlayerTime( ply, totalTime, joined, duration )

        ply:SetNW2Bool( "CFC_Time_PlayerInitialized", true )
    end
end

function ctime:untrackPlayer( steamID64 )
    logger:debug( "Untracking player ", steamID64 )

    self.sessions[steamID64] = nil
    self.sessionIDs[steamID64] = nil
    self.totalTimes[steamID64] = nil
    steamID64ToPly[steamID64] = nil
end

function ctime:updateTimes()
    local batch = {}
    local now = getNow()
    local sessionIDToSteamID64 = {}
    local timeDelta = now - self.lastUpdate

    local sessionIDs = self.sessionIDs
    local totalTimes = self.totalTimes

    for steamID64, data in pairs( self.sessions ) do
        local joined = data.joined
        local departed = data.departed

        local sessionTime = ( departed or now ) - joined
        data.duration = sessionTime

        local sessionID = sessionIDs[steamID64]
        batch[sessionID] = data

        local ply = steamID64ToPly[steamID64]
        sessionIDToSteamID64[sessionID] = steamID64

        if IsValid( ply ) then
            local newTotal = totalTimes[steamID64] + timeDelta
            totalTimes[steamID64] = newTotal
        else
            logger:debug( "Player is invalid in updateTimes, setting departed", steamID64 )
            totalTimes[steamID64] = nil
            data.departed = departed or now
        end
    end

    self.lastUpdate = now

    if table.IsEmpty( batch ) then return end

    logger:debug( "Updating " .. table.Count( batch ) .. " sessions:" )
    logger:debug( batch )

    storage:UpdateBatch( batch, function()
        for sessionID, data in pairs( batch ) do
            if data.departed then
                local steamID64 = sessionIDToSteamID64[sessionID]
                self:untrackPlayer( steamID64 )
            end
        end

        self:broadcastTimes()
    end )
end

function ctime:startTimer()
    logger:debug( "Starting timer" )

    local function timeUpdater()
        ProtectedCall( function()
            ctime:updateTimes()
        end )
    end

    timer.Create(
        self.updateTimerName,
        CFCTime.Config.get( "UPDATE_INTERVAL" ),
        0,
        timeUpdater
    )
end

function ctime:stopTimer()
    logger:debug( "Stopping timer" )
    timer.Remove( self.updateTimerName )
end

function ctime:initPlayer( ply )
    local now = getNow()
    local steamID64 = ply:SteamID64()

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

        ctime.totalTimes[steamID64] = sessionTotalTime
    end

    storage:PlayerInit( ply, now, function( data )
        logger:debug( "Player init data: ", ply, data )

        local isFirstVisit = data.isFirstVisit
        local sessionID = data.sessionID

        steamID64ToPly[steamID64] = ply
        ctime.sessionIDs[steamID64] = sessionID
        ctime.sessions[steamID64] = { joined = now }

        if isFirstVisit then return setupPly( 0, true ) end

        storage:GetTotalTime( steamID64, function( total )
            logger:debug( "Got total time for ", ply, total )
            setupPly( total, false )
        end )
    end )
end

function ctime:cleanupPlayer( ply )
    logger:debug( "Setting player departed after disconnect: ", ply )
    -- TODO: Verify bug report from the wiki: https://wiki.facepunch.com/gmod/GM:PlayerDisconnected
    local now = getNow()
    local steamID64 = ply:SteamID64()

    if not steamID64 then
        logger:error( "Player " .. ply:GetName() .. " did not have a steamID64 on disconnect" )
        return
    end

    logger:debug( "Player " .. ply:GetName() .. " ( " .. steamID64 .. " ) left at " .. now )

    if not self.sessions[steamID64] then
        logger:error( "No pending update for above player, did they leave before database returned?" )
        return
    end

    self.sessions[steamID64].departed = now
end

hook.Add( "Think", "CFC_Time_Init", function()
    hook.Remove( "Think", "CFC_Time_Init" )
    ctime:startTimer()
end )

hook.Add( "PlayerFullLoad", "CFC_Time_PlayerInit", function( ply )
    if ply:IsBot() then return end

    logger:debug( "Player fully loaded: ", ply )
    ctime:initPlayer( ply )
end )

hook.Add( "PlayerDisconnected", "CFC_Time_PlayerCleanup", function( ply )
    if ply:IsBot() then return end

    logger:debug( "Player disconnected: ", ply )
    ctime:cleanupPlayer( ply )
end )
