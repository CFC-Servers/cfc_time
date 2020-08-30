local storage = CFCTime.Storage
local logger = CFCTime.Logger
local config = CFCTime.Config

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

storage.preparedQueries = {}

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

function storage:CacheMaxSessionDuration()
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
    local createSessions = string.format( [[
        CREATE TABLE IF NOT EXISTS sessions(
            id       MEDIUMINT   UNSIGNED PRIMARY KEY AUTO_INCREMENT,
            realm    VARCHAR(10)          NOT NULL,
            user_id  VARCHAR(20)          NOT NULL,
            joined   INT         UNSIGNED NOT NULL,
            departed INT         UNSIGNED,
            duration %s                   NOT NULL DEFAULT 0,
            FOREIGN KEY (user_id) REFERENCES users (steam_id) ON DELETE CASCADE
        )
    ]], config.get( "MYSQL_SESSION_DURATION_COLUMN_TYPE" ) )

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
