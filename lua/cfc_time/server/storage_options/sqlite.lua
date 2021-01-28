include( "utils/sqlite.lua" )

local storage = CFCTime.Storage
local logger = CFCTime.Logger
local utils = CFCTime.Utils

local SQL_NULL = {}

hook.Add( "PostGamemodeLoaded", "CFC_Time_DBInit", function()
    logger:info( "Gamemoded loaded, beginning database init..." )
    storage:SetupTables()
    storage:RunSessionCleanup()
end )

--[ API Begins Here ]--

function storage:UpdateBatch( batchData )
    if not batchData then return end
    if table.IsEmpty( batchData ) then return end

    sql.Begin()

    for sessionID, data in pairs( batchData ) do
        local updateStr = Utils:buildSessionUpdate( sessionID, data )
        sql.Query( updateStr )
    end

    sql.Commit()
end

function storage:GetTotalTime( steamID, callback )
    local data = self:QueryTotalTime( steamID )
    local sum = data[1]["SUM(duration)"]

    if callback then callback( sum ) end

    return sum
end

function storage:CreateSession( steamID, sessionStart, duration )
    local sessionEnd = sessionStart + duration
    self:QueryCreateSession( steamID, sessionStart, sessionEnd, duration )
end

function storage:PlayerInit( ply, sessionStart, callback )
    local steamID = ply:SteamID64()

    logger:info( "Receiving PlayerInit call for: " .. tostring( steamID ) )

    sql.Begin()

    local isFirstVisit = self:QueryGetUser( steamID ) == nil
    self:QueryCreateUser( steamID )
    self:QueryCreateSession( steamID, sessionStart, SQL_NULL, 0 )

    sql.Commit()

    local sessionID = tonumber( self:QueryLatestSessionId()[1]["last_insert_rowid()"] )

    local response = {
        isFirstVisit = isFirstVisit,
        sessionID = sessionID
    }

    callback( response )
end
