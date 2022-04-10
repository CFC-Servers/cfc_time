CFCTime.Utils = {}

local storage = CFCTime.Storage
local utils = CFCTime.Utils

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

function utils:buildSessionUpdate( id, data )
    local query = "UPDATE cfc_time_sessions SET "

    local first = true
    for k, v in pairs( data ) do
        if not first then
            query = query .. ", "
        end
        first = false

        query = query .. k .. " = " .. escapeArg( v )
    end

    return query .. string.format( " WHERE id=%s", escapeArg( id ) )
end

function storage:CreateUsersTable()
    sql.Query( [[
        CREATE TABLE IF NOT EXISTS cfc_time_users(
            steam_id TEXT PRIMARY KEY
        )
    ]] )
end

function storage:CreateSessionsTable()
    sql.Query( [[
        CREATE TABLE IF NOT EXISTS cfc_time_sessions(
            id       INTEGER       PRIMARY KEY,
            realm    TEXT          NOT NULL,
            user_id  TEXT          NOT NULL,
            joined   INT           NOT NULL,
            departed INT,
            duration INT           NOT NULL DEFAULT 0,
            FOREIGN KEY (user_id) REFERENCES cfc_time_users (steam_id) ON DELETE CASCADE
        )
    ]] )
end

function storage:SetupTables()
    sql.Begin()

    self:CreateUsersTable()
    self:CreateSessionsTable()

    sql.Commit()
end

function storage:RunSessionCleanup()
    queryFormat( [[
        UPDATE cfc_time_sessions
        SET departed = (joined + duration)
        WHERE departed IS NULL AND realm = %s;
    ]], self.realm )
end

function storage:QueryCreateSession( steamID, sessionStart, sessionEnd, duration )
    return queryFormat( [[
        INSERT INTO cfc_time_sessions (user_id, joined, departed, duration, realm) VALUES(%s, %s, %s, %s, %s)
    ]], steamID, sessionStart, sessionEnd, duration, self.realm )
end

function storage:QueryGetUser( steamID )
    return queryFormat(
        "SELECT * FROM cfc_time_users WHERE steam_id = %s",
        steamID
    )
end

function storage:QueryCreateUser( steamID )
    return queryFormat(
        "INSERT INTO cfc_time_users (steam_id) VALUES(%s) ON CONFLICT (steam_id) DO NOTHING",
        steamID
    )
end

function storage:QueryTotalTime( steamID )
    return queryFormat( [[
        SELECT SUM(duration)
        FROM cfc_time_sessions
        WHERE user_id = %s
        AND realm = %s
    ]], steamID, self.realm )
end

function storage:QueryLatestSessionId()
    return queryFormat( [[
        SELECT last_insert_rowid()
    ]] )
end

