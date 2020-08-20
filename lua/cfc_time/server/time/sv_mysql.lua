require( "mysqloo" )

CFCTime.SQL.database = mysqloo.connect( "host", "username", "password", "cfc_time" )

function CFCTime.SQL:InitTransaction()
    local transaction = self.database:createTransaction()

    transaction.onError = function( _, err )
        self.Logger:error( err )
    end

    return transaction
end

function CFCTime.SQL:InitQuery( sql )
    local query = self.database:query( sql )

    query.onError = function( _, ... )
        CFCTime.Logger:error( ... )
    end

    return query
end

function CFCTime.SQL.database:onConnected()
    CFCTime.Logger:info( "DB successfully connected! Beginning init..." )

    local transaction = CFCTime.SQL:InitTransaction()

    local createUsers = [[
        CREATE TABLE IF NOT EXISTS users(
            steam_id VARCHAR(20) PRIMARY KEY
        );
    ]]
    local createUsersQuery = self:query( createUsers )

    local createSessions = [[
        CREATE TABLE IF NOT EXISTS sessions(
            id       INT                  PRIMARY KEY AUTO_INCREMENT,
            realm    VARCHAR(10)          NOT NULL,
            user_id  VARCHAR(20)          NOT NULL,
            start    INT         UNSIGNED NOT NULL,
            end      INT         UNSIGNED NOT NULL,
            duration MEDIUMINT   UNSIGNED NOT NULL DEFAULT 0,
            FOREIGN KEY (user_id) REFERENCES users (steam_id) ON DELETE CASCADE
        )
    ]]
    local createSessionsQuery = self:query( createSessions )

    local cleanupMissingEndTimes = [[
        UPDATE sessions
        SET end = start + duration
        WHERE end IS NULL
    ]]
    local cleanupMissingEndTimesQuery = self:query( cleanupMissingEndTimes )

    transaction:addQuery( createUsersQuery )
    transaction:addQuery( createSessionsQuery )
    transaction:addQuery( cleanupMissingEndTimesQuery )

    transaction:start()
end

function CFCTime.SQL.database:onConnectionFailed( _, err )
    CFCTime.Logger:error( "Failed to connect to database!" )
    CFCTime.Logger:fatal( err )
end

hook.Add( "PostGamemodeLoaded", "CFC_Time_DBInit", function()
    CFCTime.Logger:log( "Gamemoded loaded, beginning database init..." )
    CFCTime.SQL.database:connect()
end )

function CFCTime.SQL:BuildSessionUpdate( data, id )
    local updateSection = "UPDATE sessions "
    local setSection = "SET "
    local whereSection = "WHERE id = " .. id

    local count = table.Count( data )
    local idx = 1
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

    return query
end

--[ API Begins Here ]--

function CFCTime.SQL:UpdateBatch( batchData )
    local transaction = CFCTime.SQL:InitTransaction()

    for sessionId, data in pairs( batchData ) do
        local updateStr = self:BuildSessionUpdate( data, sessionId )
        local query = self.database:query( updateStr )

        transaction:addQuery( query )
    end

    transaction:start()
end

function CFCTime.SQL:GetTotalTime( steamId, cb )
    local queryStr = "SELECT SUM(duration) FROM sessions WHERE user_id = " .. steamId
    local query = self:InitQuery( queryStr )

    query.onSuccess = function( _, data )
        cb( data )
    end
end

function CFCTime.SQL:NewUserSession( steamId, cb )
    local transaction = CFCTime.SQL:InitTransaction()

    -- Only insert if they don't exist
    local preparedNewUser = self.database:prepare( "INSERT IGNORE INTO users (steam_id) VALUES(?)")
    preapredNewUser:setString(1, steamId)

    local preparedNewSession = self.database:prepare( "INSERT INTO sessions (user_id, start) VALUES(?, ?)" )
    preparedNewSession:setString(1, steamId)
    preparedNewSession:setNumber(2, sessionStart)

    transaction:addQuery( preparedNewUser )
    transaction:addQuery( preparedNewSession )

    transaction.onSuccess = function( _, data )
        cb( data )
    end

    transaction:start()
end
