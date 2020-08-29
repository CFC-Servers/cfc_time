require( "mysqloo" )

local storage = CFCTime.Storage
local logger = CFCTime.Logger
local config = CFCTime.Config

config.setDefaults{
    mysql_host = "127.0.0.1",
    mysql_username = "",
    mysql_password = "",
    mysql_database = "cfc_time"
}

storage.database = mysqloo.connect(
    config.get( "mysql_host" ),
    config.get( "mysql_username" ),
    config.get( "mysql_password" ),
    config.get( "mysql_database" )
)

storage.preparedQueries = {}
storage.MAX_SESSION_DURATION = nil

local MAX_SESSION_DURATIONS = {
    tinyint = {
        signed = 127,
        unsigned = 255
    },

    smallint = {
        signed = 32767,
        unsigned = 65535
    },

    mediumint = {
        signed = 8388607,
        unsigned = 16777215
    },

    int = {
        signed = 2147483647,
        unsigned = 4294967295
    },

    bigint = {
        signed = math.huge,
        unsigned = math.huge
    }
}

function storage:InitTransaction()
    local transaction = self.database:createTransaction()

    transaction.onError = function( _, err )
        logger:error( err )
    end

    return transaction
end

function storage:InitQuery( rawQuery )
    local query = self.database:query( rawQuery )

    query.onError = function( _, err, errQuery )
        logger:error( err, errQuery )
    end

    return query
end

function storage:GetMaxSessionTime( callback )
    local queryStr = [[
        SELECT COLUMN_TYPE
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = "sessions"
        AND COLUMN_NAME = "duration"
    ]]

    local query = self:InitQuery( queryStr )

    local maxSessionTime = function( data )
        -- e.g.
        -- "mediumint(8)"
        -- "mediumint(8) unsigned"
        local columnData = data[1].COLUMN_TYPE

        -- e.g.
        -- { [1] = "mediumint(8)" }
        -- { [1] = "mediumint(8)", [2] = "unsigned" }
        local spl = string.Split( columnData, " " )

        -- e.g.
        -- "mediumint"
        -- "mediumint"
        local column = string.Split( spl[1], "(" )[1]

        -- e.g.
        -- true
        -- false
        local signed = spl[2] ~= "unsigned"

        logger:debug( "Getting max session duration for column: [" .. column .. "] (signed: " .. tostring( signed ) .. ")" )
        return MAX_SESSION_DURATIONS[column][signed and "signed" or "unsigned"]
    end

    query.onSuccess = function( _, data )
        if data then
            logger:debug( "Session duration query result", data )
        end

        local maxTime = maxSessionTime( data )

        callback( maxTime )
    end

    query:start()
end

function storage:SetMaxSessionTime()
    self:GetMaxSessionTime(
        function( maxSessionTime )
            logger:debug( "Setting max session duration to: " .. maxSessionTime )
            storage.MAX_SESSION_DURATION = maxSessionTime
        end
    )
end

function storage:CreateUsersQuery()
    local createUsers = [[
        CREATE TABLE IF NOT EXISTS users(
            id       MEDIUMINT   UNSIGNED PRIMARY KEY AUTO_INCREMENT,
            steam_id VARCHAR(20) UNIQUE   NOT NULL,
            INDEX    (steam_id)
        );
    ]]

    return self.database:query( createUsers )
end

function storage:CreateSessionsQuery()
    local createSessions = [[
        CREATE TABLE IF NOT EXISTS sessions(
            id       MEDIUMINT   UNSIGNED PRIMARY KEY AUTO_INCREMENT,
            realm    VARCHAR(10)          NOT NULL,
            user_id  VARCHAR(20)          NOT NULL,
            joined   INT         UNSIGNED NOT NULL,
            departed INT         UNSIGNED,
            duration MEDIUMINT   UNSIGNED NOT NULL DEFAULT 0,
            FOREIGN KEY (user_id) REFERENCES users (steam_id) ON DELETE CASCADE
        )
    ]]

    return self.database:query( createSessions )
end

function storage:SessionCleanupQuery()
    local fixMissingDepartedTimes = string.format( [[
        UPDATE sessions
        SET departed = (joined + duration)
        WHERE departed IS NULL
        AND realm = '%s'
    ]], self.realm )

    return self.database:query( fixMissingDepartedTimes )
end

function storage:AddPreparedStatement( name, query )
    local statement = self.database:prepare( query )

    statement.onError = function( _, err, errQuery )
        logger:error( "An error has occured in a prepared statement!", err, errQuery )
    end

    statement.onSuccess = function()
        logger:debug( "Created prepared statement of name: " .. name .. " with query: [[ " .. query .. " ]]" )
    end

    self.preparedQueries[name] = statement
end

function storage:PrepareStatements()
    logger:info( "Constructing prepared statements..." )

    local realm = self.realm

    local newUser = "INSERT INTO users (steam_id) VALUES(?) ON DUPLICATE KEY UPDATE id=id"

    local newSession = string.format( [[
        INSERT INTO sessions (user_id, joined, departed, duration, realm) VALUES(?, ?, ?, ?, '%s')
    ]], realm )

    local totalTime = string.format( [[
        SELECT SUM(duration)
        FROM sessions
        WHERE user_id = ?
        AND realm = '%s'
        FOR UPDATE
    ]], realm )

    local sessionUpdate = [[
        UPDATE sessions
        SET
          joined = IFNULL(?, joined),
          departed = IFNULL(?, departed),
          duration = IFNULL(?, duration)
        WHERE
          id = ?
    ]]

    self:AddPreparedStatement( "newUser", newUser )
    self:AddPreparedStatement( "newSession", newSession )
    self:AddPreparedStatement( "totalTime", totalTime )
    self:AddPreparedStatement( "sessionUpdate", sessionUpdate )
end

function storage:Prepare( statementName, onSuccess, ... )
    local query = self.preparedQueries[statementName]
    query:clearParameters()

    for k, v in pairs( { ... } ) do
        if isnumber( v ) then
            query:setNumber( k, v )
        elseif isstring( v ) then
            query:setString( k, v )
        elseif isbool( v ) then
            query:setBoolean( k, v )
        elseif v == nil then
            query:setNull( k )
        else
            error( "Wrong data type passed to Prepare statement!: " .. v )
        end
    end

    if onSuccess then query.onSuccess = onSuccess end

    return query
end

function storage.database:onConnected()
    logger:info( "DB successfully connected! Beginning init..." )

    local transaction = storage:InitTransaction()

    transaction:addQuery( storage:CreateUsersQuery() )
    transaction:addQuery( storage:CreateSessionsQuery() )
    transaction:addQuery( storage:SessionCleanupQuery() )

    transaction.onSuccess = function()
        storage:SetMaxSessionTime()
        storage:PrepareStatements()
    end

    transaction:start()
end

function storage.database:onConnectionFailed( err )
    logger:error( "Failed to connect to database!" )
    logger:fatal( err )
end

hook.Add( "PostGamemodeLoaded", "CFC_Time_DBInit", function()
    logger:info( "Gamemoded loaded, beginning database init..." )
    storage.database:connect()
end )

--[ API Begins Here ]--

function storage:UpdateBatch( batchData )
    if not batchData then return end
    if table.IsEmpty( batchData ) then return end

    local transaction = storage:InitTransaction()

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

function storage:CreateSession( callback, steamID, sessionStart, sessionEnd, sessionDuration )
    local maxDuration = self.MAX_SESSION_DURATION
    local sessionsCount = math.ceil( maxDuration / sessionDuration )
    if sessionsCount == math.huge then sessionsCount = 1 end

    logger:debug( "[" .. tostring( steamID ) .. "] Creating " .. tostring( sessionsCount ) .. " sessions to accomodate duration of: " .. tostring( sessionDuration ) )

    local transaction = self:InitTransaction()
    transaction.onSuccess = function()
        if callback then callback() end
    end

    local function addSession( duration, newStart, newEnd )
        local debugLine = "Queueing new session of duration: %d ( start: %d | end: %d )"
        logger.debug( string.format( debugLine, duration, newStart, newEnd ) )

        local newSession = self:Prepare( "newSession", nil, steamID, newStart, newEnd, duration )
        transaction:addQuery( newSession )
    end

    for i = 1, sessionsCount do
        local usedDuration = maxDuration * ( i - 1 )

        local newDuration = sessionDuration - usedDuration
        local newStart = sessionStart + usedDuration
        local newEnd = newStart + newDuration

        addSession( newDuration, newStart, newEnd )
    end

    transaction:start()
end

-- Takes a player, a session start timestamp, and a callback, then:
--  - Creates a new user (if needed)
--  - Creates a new session with given values
-- Calls callback with a structure containing:
--  - sessionID (the id of the newly created session)
--  - totalTime (the calculated total playtime)
function storage:PlayerInit( ply, sessionStart, callback )
    local steamID = ply:SteamID64()

    logger:info( "Receiving PlayerInit call for: " .. tostring( steamID ) )
    local transaction = storage:InitTransaction()

    local newUser = self:Prepare( "newUser", nil, steamID )
    local newSession = self:Prepare( "newSession", nil, steamID, sessionStart, nil, 0 )

    transaction:addQuery( newUser )
    transaction:addQuery( newSession )

    transaction.onSuccess = function()
        logger:debug( "PlayerInit transaction successful!" )

        local isFirstVisit = newUser:lastInsert() ~= 0
        local sessionIDResult = newSession:lastInsert()
        logger:debug( "NewUser last inserted index: " .. tostring( newUser:lastInsert() ) )

        local data =  {
            isFirstVisit = isFirstVisit,
            sessionID = sessionIDResult
        }

        callback( data )
    end

    transaction:start()
end
