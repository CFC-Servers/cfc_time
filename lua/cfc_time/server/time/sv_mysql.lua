require( "mysqloo" )

-- TODO: Make a config module that will load the connection settings properly
-- TODO: Load/Set the realm
local storage = CFCTime.Storage
local logger = CFCTime.Logger

storage.database = mysqloo.connect( "host", "username", "password", "cfc_time" )
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
            steam_id VARCHAR(20) PRIMARY KEY
        );
    ]]

    return self.database:query( createUsers )
end

function storage:CreateSessionsQuery()
    local createSessions = [[
        CREATE TABLE IF NOT EXISTS sessions(
            id       INT                  PRIMARY KEY AUTO_INCREMENT,
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

    local newUser = "INSERT IGNORE INTO users (steam_id) VALUES(?)"

    local newSession = string.format( [[
        INSERT INTO sessions (user_id, joined, departed, duration, realm) VALUES(?, ?, ?, ?, '%s'); SELECT LAST_INSERT_ID()
    ]], realm )

    local totalTime = string.format( [[
        SELECT SUM(duration)
        FROM sessions
        WHERE user_id = ?
        AND realm = '%s'
    ]], realm )

    self:AddPreparedStatement( "newUser", newUser )
    self:AddPreparedStatement( "newSession", newSession )
    self:AddPreparedStatement( "totalTime", totalTime )
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

-- TODO: Find a better/safer way to do this
function storage:BuildSessionUpdate( data, id )
    local updateSection = "UPDATE sessions "
    local setSection = "SET "
    local whereSection = string.format(
        "WHERE id = %s", id
    )

    -- TODO: Have a safeguard here for invalid keys?
    local count = table.Count( data )
    local idx = 1

    -- FIXME: This will break because we pass strings/ints interchangeably, but strings need quotes around them
    for k, v in pairs( data ) do
        local newSet = k .. " = " .. v

        if idx ~= count then
            -- Add a comma if it isn't the last one
            newSet = newSet .. ","
        else
            -- Add a space if it's the last one
            newSet = newSet .. " "
        end

        setSection = setSection .. newSet
        idx = idx + 1
    end

    local query = updateSection .. setSection .. whereSection

    logger:info( "Created sessions update query!" )
    logger:info( self.database:escape( query ) )

    return self.database:escape( query )
end

--[ API Begins Here ]--

function storage:UpdateBatch( batchData )
    if not batchData then return end
    if table.Count( batchData ) == 0 then return end

    local transaction = storage:InitTransaction()

    for sessionId, data in pairs( batchData ) do
        local updateStr = self:BuildSessionUpdate( data, sessionId )
        local query = self.database:query( updateStr )

        transaction:addQuery( query )
    end

    transaction:start()
end

function storage:GetTotalTime( steamId, callback )
    local onSuccess = function( _, data )
        callback( data )
    end

    local query = self:Prepare( "totalTime", onSuccess, steamId )

    query:start()
end

function storage:CreateSession( callback, steamId, sessionStart, sessionEnd, duration )
    local newSession = self:Prepare( "newSession", callback, steamId, sessionStart, sessionEnd, duration )
    newSession:start()
end

-- Takes a steamid, a session start timestamp, and a callback, then:
--  - Creates a new user (if needed)
--  - Creates a new session with given values
-- Calls callback with a structure containing:
--  - sessionId (the id of the newly created session)
--  - totalTime (the calculated total playtime)
function storage:PlayerInit( steamId, sessionStart, callback )
    logger:info( "Receiving PlayerInit call for: " .. tostring( steamId ) )
    local transaction = storage:InitTransaction()

    local newUser = self:Prepare( "newUser", nil, steamId )
    local newSession = self:Prepare( "newSession", nil, steamId, sessionStart, nil, 0 )
    local totalTime = self:Prepare( "totalTime", nil, steamId )

    transaction:addQuery( newUser )
    transaction:addQuery( newSession )
    transaction:addQuery( totalTime )

    transaction.onSuccess = function( t )
        logger:info( "PlayerInit transaction successful!" )
        local totalTimeResult = totalTime:getData()[1]["SUM(duration)"]
        logger:debug( table.ToString( newSession:GetData(), nil, true ) )
        local sessionId = newSession:getData()[1]["id"]

        local response = {
            totalTime = totalTimeResult,
            sessionId = sessionId
        }

        callback( response )
    end

    transaction:start()
end
