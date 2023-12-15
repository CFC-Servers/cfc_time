CFCTime.ctime = CFCTime.ctime or {}

local ctime = CFCTime.ctime
local logger = CFCTime.Logger
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
local steamIDToPly = {}

function ctime:broadcastPlayerTime( ply, totalTime, joined, duration )
    ply:SetNW2Float( "CFC_Time_TotalTime", totalTime )
    ply:SetNW2Float( "CFC_Time_SessionStart", joined )
    ply:SetNW2Float( "CFC_Time_SessionDuration", duration )

    hook.Run( "CFC_Time_PlayerTimeUpdated", ply, totalTime, joined, duration )
end

function ctime:broadcastTimes()
    local sessions = self.sessions

    for steamID, totalTime in pairs( self.totalTimes ) do
        local ply = steamIDToPly[steamID]

        if IsValid( ply ) then
            local session = sessions[steamID]

            local joined = session.joined
            local duration = session.duration

            self:broadcastPlayerTime( ply, totalTime, joined, duration )

            ply:SetNW2Bool( "CFC_Time_PlayerInitialized", true )
        end
    end
end

function ctime:untrackPlayer( steamID )
    self.sessions[steamID] = nil
    self.sessionIDs[steamID] = nil
    self.totalTimes[steamID] = nil
    steamIDToPly[steamID] = nil
end

function ctime:updateTimes()
    local batch = {}
    local now = getNow()
    local timeDelta = now - self.lastUpdate

    local sessionIDs = self.sessionIDs
    local totalTimes = self.totalTimes

    for steamID, data in pairs( self.sessions ) do
        local joined = data.joined
        local departed = data.departed

        -- If they've departed and we already saved the session to the DB, we can skip and untrack
        if departed and departed < self.lastUpdate then
            self:untrackPlayer( steamID )
        else
            local sessionTime = ( departed or now ) - joined
            data.duration = sessionTime

            local sessionID = sessionIDs[steamID]
            batch[sessionID] = data

            -- Players may not have a total time if they weren't set up successfully
            local currentTotal = totalTimes[steamID]
            if currentTotal then
                local newTotal = currentTotal + timeDelta
                totalTimes[steamID] = newTotal
            end
        end
    end

    self.lastUpdate = now

    if table.IsEmpty( batch ) then return end

    logger:debug( "Updating " .. table.Count( batch ) .. " sessions:" )
    logger:debug( batch )

    storage:UpdateBatch( batch )
    self:broadcastTimes()
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
    timer.Remove( self.updateTimerName )
end

function ctime:initPlayer( ply )
    local now = getNow()
    local steamID = ply:SteamID64()

    local function setupPly( totalTime, isFirstVisit, lastSession )
        local sessionTotalTime = totalTime + ( getNow() - now )

        local initialTime = { seconds = 0 }

        initialTime.add = function( seconds )
            initialTime.seconds = initialTime.seconds + seconds
        end

        initialTime.set = function( seconds )
            initialTime.seconds = seconds
        end

        hook.Run( "CFC_Time_PlayerInitialTime", ply, isFirstVisit, initialTime, lastSession )
        sessionTotalTime = sessionTotalTime + initialTime.seconds

        ctime.totalTimes[steamID] = sessionTotalTime
        ctime:broadcastPlayerTime( ply, sessionTotalTime, now, 0 )
    end

    local existingSession = self.sessions[steamID]
    if existingSession then
        ErrorNoHaltWithStack( "[CFCTime] Player loaded in, but already had a session? " .. steamID )
        self:untrackPlayer( steamID )
    end

    storage:PlayerInit( ply, now, function( data )
        local lastSession = data.lastSession
        local sessionID = data.sessionID

        local session = { joined = now }
        steamIDToPly[steamID] = ply
        ctime.sessions[steamID] = session
        ctime.sessionIDs[steamID] = sessionID

        if not IsValid( ply ) then
            session.departed = now
            logger:warn( "Player left before their session was created? Marking them as departed", steamID )
            return
        end

        -- If they don't have any previous sessions on this realm, this is their first visit
        if not lastSession then
            return setupPly( 0, true, lastSession )
        end

        storage:GetTotalTime( steamID, function( total )
            setupPly( total, false, lastSession )
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

    logger:debug( "Player " .. ply:GetName() .. " ( " .. steamID .. " ) left at " .. now )

    if not self.sessions[steamID] then
        logger:error( "No pending update for above player, did they leave before database returned?" )
        return
    end

    self.sessions[steamID].departed = now
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
