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

    storage:CreateUsersTable()
    storage:CreateSessionsTable()

    sql.Commit()
end

hook.Add( "PostGamemodeLoaded", "CFC_Time_DBInit", function()
    logger:info( "Gamemoded loaded, beginning database init..." )
    storage:RunSessionCleanup()
    storage:SetupTables()
end )

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

function storage:GetTotalTime( steamID, callback )
    local data = storage:QueryTotalTime( steamID )

    callback( data[1]["SUM(duration)"] )
end

function storage:CreateSession( callback, steamID, sessionStart, sessionEnd, duration )
    local newSession = storage:QueryCreateSession( steamID, sessionStart, sessionEnd, duration )

    if callback then callback( newSession ) end
end

function storage:PlayerInit( ply, sessionStart, callback )
    local steamID = ply:SteamID64()

    logger:info( "Receiving PlayerInit call for: " .. tostring( steamID ) )

    sql.Begin()

    local userExisted = storage:QueryGetUser( steamID ) ~= nil
    storage:QueryCreateUser( steamID )
    storage:QueryCreateSession( steamID, sessionStart, SQL_NULL, 0 )

    local totalTime = tonumber( storage:QueryTotalTime( steamID )[1]["SUM(duration)"] )
    local sessionId = tonumber( storage:QueryLatestSessionId()[1]["last_insert_rowid()"] )

    sql.Commit()

    if not userExisted then
        local newInitialTime = hook.Run( "CFC_Time_NewPlayer", ply )
        totalTime = newInitialTime or totalTime
    end

    local response = {
        totalTime = totalTime,
        sessionId = sessionId
    }

    callback( response )
end
