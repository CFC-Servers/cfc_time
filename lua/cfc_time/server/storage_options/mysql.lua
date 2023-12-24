require( "mysqloo" )
include( "utils/mysql.lua" )

local storage = CFCTime.Storage
local logger = CFCTime.Logger
local config = CFCTime.Config

config.setDefaults{
    MYSQL_HOST = "127.0.0.1",
    MYSQL_USERNAME = "",
    MYSQL_PASSWORD = "",
    MYSQL_DATABASE = "cfc_time",
    MYSQL_PORT = 3306
}

storage.database = mysqloo.connect(
    config.get( "MYSQL_HOST" ),
    config.get( "MYSQL_USERNAME" ),
    config.get( "MYSQL_PASSWORD" ),
    config.get( "MYSQL_DATABASE" ),
    config.get( "MYSQL_PORT" )
)

function storage.database:onConnected()
    logger:info( "DB successfully connected! Beginning init..." )

    local transaction = storage:InitTransaction()

    transaction:addQuery( storage:CreateUsersQuery() )
    transaction:addQuery( storage:CreateSessionsQuery() )
    transaction:addQuery( storage:SessionCleanupQuery() )

    transaction.onSuccess = function()
        storage:PrepareStatements()
    end

    transaction:start()
end

function storage.database:onConnectionFailed( err )
    -- TODO: Test this
    error( "CFCTime: Failed to connect to database! '" .. err .. "'" )
end

hook.Add( "PostGamemodeLoaded", "CFC_Time_DBInit", function()
    logger:info( "Gamemoded loaded, beginning database init..." )
    storage.database:connect()
end )

--[ API Begins Here ]--

function storage:UpdateBatch( batchData, callback )
    if not batchData then return callback() end
    if table.IsEmpty( batchData ) then return callback() end

    local transaction = storage:InitTransaction()
    transaction.onSuccess = callback

    for sessionID, data in pairs( batchData ) do
        local query = self:Prepare(
            "sessionUpdate",
            nil,
            data.joined,
            data.departed,
            data.duration,
            sessionID
        )

        transaction:addQuery( query )
    end

    transaction:start()
end

function storage:GetTotalTime( steamID, callback )
    local onSuccess = function( _, data )
        callback( data[1]["SUM(duration)"] )
    end

    local query = self:Prepare( "totalTime", onSuccess, steamID )

    query:start()
end

function storage:CreateSession( steamID, sessionStart, sessionDuration )
    local maxDuration = self.MAX_SESSION_DURATION
    local sessionsCount = math.max( 1, math.ceil( sessionDuration / maxDuration ) )

    logger:debug(
        string.format(
            "[%s] Creating %d sessions to accomodate duration of %d",
            steamID,
            sessionsCount,
            sessionDuration
        )
    )

    local function addSession( duration, newStart, newEnd )
        logger:debug(
            string.format(
                "Queueing new session of duration: %d ( start: %d | end: %d )",
                duration,
                newStart,
                newEnd
            )
        )

        -- Because we use the same prepared query repeatedly, we need to run them in individual
        -- transactions or they'll all use the values given to the last one. This is a weird bug in MySQLOO
        local newSessionTransaction = self:InitTransaction()
        local newSession = self:Prepare( "newSession", nil, steamID, newStart, newEnd, duration )

        newSessionTransaction:addQuery( newSession )
        newSessionTransaction:start()
    end

    for i = 1, sessionsCount do
        local usedDuration = maxDuration * ( i - 1 )

        local newDuration = math.min( sessionDuration - usedDuration, maxDuration )
        local newStart = sessionStart + usedDuration
        local newEnd = newStart + newDuration

        addSession( newDuration, newStart, newEnd )
    end
end

function storage:PlayerInit( ply, sessionStart, callback )
    local steamID = ply:SteamID64()

    logger:debug( "Receiving PlayerInit call for: " .. tostring( steamID ) )
    local transaction = storage:InitTransaction()

    local newUser = self:Prepare( "newUser", nil, steamID )
    local newSession = self:Prepare( "newSession", nil, steamID, sessionStart, nil, 0 )

    transaction:addQuery( newUser )
    transaction:addQuery( newSession )

    transaction.onSuccess = function()
        logger:debug( "PlayerInit transaction successful!" )

        local isFirstVisit = newUser:lastInsert() ~= 0
        local sessionID = newSession:lastInsert()
        logger:debug( "NewUser last inserted index: " .. tostring( newUser:lastInsert() ) )

        local data =  {
            isFirstVisit = isFirstVisit,
            sessionID = sessionID
        }

        callback( data )
    end

    transaction:start()
end
