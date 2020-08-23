local storage = CFCTime.Storage
local logger = CFCTime.Logger

local SQL_NULL = {}

local function escapeArg( arg )
    if arg == SQL_NULL then
        return "NULL"
    elseif type( arg ) == "number" then
        return arg
    else
        return sql.SQLStr( arg )
    end
end

local function queryFormat( query, ... )
    local args = {}
    for i, arg in ipairs{ ... } do
        args[i] = escapeArg( arg )
    end

    query = string.format( query, unpack( args ) )
    return sql.Query( query )
end

local function buildSessionUpdate( id, data )
    local query = "UPDATE cfc_time_sessions SET "

    local first = true
    for k, v in pairs( data ) do
        if not first then
            query = query .. ", "
        end
        first = false

        query = query .. k .. " = " .. escapeArg( v )
    end

    return query .. string.format( " WHERE rowid=%s", escapeArg( id ) )
end

function storage:CreateUsersTable()
    sql.Query( [[
        CREATE TABLE IF NOT EXISTS cfc_timeusers(
            steam_id TEXT PRIMARY KEY
        )
    ]] )
end

function storage:CreateSessionsTable()
    sql.Query( [[
        CREATE TABLE IF NOT EXISTS cfc_time_sessions(
            realm    TEXT          NOT NULL,
            user_id  TEXT          NOT NULL,
            joined   INT           NOT NULL,
            departed INT,
            duration INT           NOT NULL DEFAULT 0,
            FOREIGN KEY (user_id) REFERENCES cfc_time_users (steam_id) ON DELETE CASCADE
        )
    ]] )
end

function storage:RunSessionCleanup()
    queryFormat( [[
        UPDATE cfc_time_sessions
        SET departed = (joined + duration)
        WHERE departed IS NULL AND realm = %s;
    ]], self.realm )
end

function storage:QueryCreateSession( steamId, sessionStart, sessionEnd, duration )
    queryFormat( [[
        INSERT INTO cfc_time_sessions (user_id, joined, departed, duration, realm) VALUES(%s, %s, %s, %s, %s)
    ]], steamId, sessionStart, sessionEnd, duration, self.realm )
end

function storage:QueryCreateUser( steamId )
    queryFormat(
        "INSERT INTO cfc_time_users (steam_id) VALUES(%s) ON CONFLICT (steam_id) DO NOTHING",
        steamId
    )
end

function storage:QueryTotalTime( steamId )
    return queryFormat( [[
        SELECT SUM(duration)
        FROM sessions
        WHERE user_id = %s
        AND realm = %s
    ]], steamId, self.realm )
end

function storage:QueryLatestSessionId()
    return queryFormat( [[
        SELECT last_insert_rowid()
    ]] )
end

--[ API Begins Here ]--

function storage:UpdateBatch( batchData )
    if not batchData then return end
    if table.IsEmpty( batchData ) then return end

    sql.Begin()

    for sessionId, data in pairs( batchData ) do
        local updateStr = buildSessionUpdate( sessionId, data )
        sql.Query( updateStr )
    end

    sql.Commit()
end

function storage:GetTotalTime( steamId, callback )
    local data = storage:QueryTotalTime( steamId )

    callback( data )
end

function storage:CreateSession( callback, steamId, sessionStart, sessionEnd, duration )
    local newSession = storage:QueryCreateSession( steamId, sessionStart, sessionEnd, duration )

    callback( newSession )
end

function storage:PlayerInit( steamId, sessionStart, callback )
    logger:info( "Receiving PlayerInit call for: " .. tostring( steamId ) )

    sql.Begin()

    storage:QueryCreateSession( steamId )
    storage:QueryNewSession( steamId, sessionStart, SQL_NULL, 0 )
    local totalTime = storage:QueryTotalTime( steamId )[1]["SUM(duration)"]
    local sessionId = storage:QueryLatestSessionId()[1]["last_insert_rowid()"]

    sql.Commit()

    local response = {
        totalTime = totalTime,
        sessionId = sessionId
    }

    callback( response )
end
