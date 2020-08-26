require( "mysqloo" )

-- TODO: Make a config module that will load the connection settings properly
-- TODO: Load/Set the realm
local storage = CFCTime.Storage
local logger = CFCTime.Logger
local config = CFCTime.Config

config.setDefaults{
    mysql_host = "127.0.0.1:3306",
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
    logger:debug( fixMissingDepartedTimes )

    return self.database:query( fixMissingDepartedTimes )
end

function storage:AddPreparedStatement( name, query )
    local statement = self.database:prepare( query )

    statement.onError = function( _, err, errQuery )
        logger:error( err, errQuery )
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

    for sessionId, data in pairs( batchData ) do
        local query = self:Prepare(
            "sessionUpdate",
            nil,
            data.joined,
            data.departed,
            data.duration,
            sessionId
        )

        transaction:addQuery( query )
    end

    transaction:start()
end

function storage:GetTotalTime( steamId, callback )
    local onSuccess = function( _, data )
        callback( data[1]["SUM(duration)"] )
    end

    local query = self:Prepare( "totalTime", onSuccess, steamId )

    query:start()
end

function storage:CreateSession( callback, steamId, sessionStart, sessionEnd, duration )
    local newSession = self:Prepare( "newSession", callback, steamId, sessionStart, sessionEnd, duration )
    newSession:start()
end

-- Takes a player, a session start timestamp, and a callback, then:
--  - Creates a new user (if needed)
--  - Creates a new session with given values
-- Calls callback with a structure containing:
--  - sessionId (the id of the newly created session)
--  - totalTime (the calculated total playtime)
function storage:PlayerInit( ply, sessionStart, callback )
    local steamId = ply:SteamID64()

    logger:info( "Receiving PlayerInit call for: " .. tostring( steamId ) )
    local transaction = storage:InitTransaction()

    local newUser = self:Prepare( "newUser", nil, steamId )
    local newSession = self:Prepare( "newSession", nil, steamId, sessionStart, nil, 0 )

    transaction:addQuery( newUser )
    transaction:addQuery( newSession )

    transaction.onSuccess = function()
        logger:debug( "PlayerInit transaction successful!" )

        local userExisted = newUser:lastInsert() == 0
        local sessionIdResult = newSession:lastInsert()
        logger:debug( "NewUser last inserted index: " .. tostring(newUser:lastInsert()))

        -- TODO: Pull this back out into the `transaction` when one of two things changes:
        --  1. MySQLOO retroactively applies bugfixes from the 9.7-Beta (64bit only) back into 9.6 (32+64bit)
        --  2. GMod merges the 64bit branch back into the main branch and releases (then we can use MySQLOO >=9.7)
        --  We have to do this because of a weird bug.
        --  Any prepared SELECT inside a transaction will always use the /first/ value given
        --  to it during that session (until it's run outside of a transaction)
        local totalTime = self:Prepare( "totalTime", function( _, data )
            local totalTimeResult = data[1]["SUM(duration)"]
            logger:debug( "Sum of existing session durations: " .. totalTimeResult or "nil" )

            if not userExisted then
                logger:debug( "User isn't in DB - running NewPlayer hook..." )

                local newInitialTime = hook.Run( "CFC_Time_NewPlayer", ply )

                logger:debug( "Received new initial time from hook: " .. tostring(newInitialTime) )

                totalTimeResult = newInitialTime or totalTimeResult
            end

            local response = {
                totalTime = totalTimeResult,
                sessionId = sessionIdResult
            }

            callback( response )

        end, steamId )

        totalTime:start()
    end

    transaction:start()
end
