local storage = CFCTime.Storage
local logger = CFCTime.Logger

local SQL_NULL = {}

local function escapeArg( arg )
    if arg == SQL_NULL then
        return "NULL"
    elseif type(arg) == "number" then
        return arg
    else
        return sql.SQLStr(arg)
    end
end

local function queryFormat( query, ... )
    local args = {}
    for i, arg in ipairs{...} do
        args[i] = escapeArg( arg )
    end

    query = string.format( query, unpack(args) )
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

    return query .. string.format(" WHERE id=%s AND realm=%s", escapeArg( id ), escapeArg( 'cfc3' ) )
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
            id       INT           PRIMARY KEY,
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

function storage:CreateSession( steamId, sessionStart, sessionEnd, duration )
    queryFormat( [[
        INSERT INTO cfc_time_sessions (user_id, joined, departed, duration, realm) VALUES(%s, %s, %s, %s, %s)
    ]], steamId, sessionStart, sessionEnd, duration, self.realm )
end

function storage:CreateUser( steamId )
    queryFormat(
        "INSERT INTO cfc_time_users (steam_id) VALUES(%s) ON CONFLICT (steam_id) DO NOTHING",
        steamId
    )
end

function storage:GetTotalTime( steamId )
    return queryFormat( [[
        SELECT SUM(duration)
        FROM sessions
        WHERE user_id = %s
        AND realm = %s
    ]], steamId, self.realm )
end

function storage:GetLatestSession()
    return queryFormat( [[
        SELECT *
        FROM sessions
        WHERE user_id = %s
        AND realm = %s
        ORDER BY joined DESC
        LIMIT 1
    ]], steamId, self.realm )
end

--[ API Begins Here ]--

function storage:UpdateBatch( batchData )
    if not batchData then return end
    if table.Count( batchData ) == 0 then return end

    sql.Begin()

    for sessionId, data in pairs( batchData ) do
        local updateStr = buildSessionUpdate( sessionId, data )
        sql.Query( updateStr )
    end

    sql.Commit()
end

function storage:GetTotalTime( steamId, callback )
    local data = storage:GetTotalTime( steamId )

    callback( data )
end

function storage:CreateSession( callback, steamId, sessionStart, sessionEnd, duration )
    local newSession = storage:CreateSession( steamId, sessionStart, sessionEnd, duration )
    callback( newSession )
end

function storage:PlayerInit( steamId, sessionStart, callback )
    logger:info( "Receiving PlayerInit call for: " .. tostring( steamId ) )
    sql.Begin()

    storage:NewUser( steamId )
    storage:NewSession( steamId, sessionStart, SQL_NULL, 0 )
    -- TODO get total time and session data
    -- TODO pass data to callback
    sql.Commit()
end
