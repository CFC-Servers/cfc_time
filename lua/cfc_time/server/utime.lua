ctime.utimeExists = sql.TableExists( "utime" )

CFCTime.Utime = CFCTime.Utime or {}

function CFCTime.Utime.getPlayerTime( ply )
    local uid = ply:UniqueID()
    local row = sql.QueryRow( "SELECT totaltime, lastvisit FROM utime WHERE player = " .. uid .. ";" )
    
    if not row then return end
    
    return row.totaltime
end

function CFCTime.Utime.onPlayerJoin( ply )
    local time = CFCTime.Utime.getPlayerTime( ply ) or 0

    ply:SetUTime( time )
    ply:SetUTimeStart( CurTime() ) 
end

function CFCTime.Utime.deleteUtimeHooks()
    hook.Remove( "PlayerInitialSpawn", "UTimeInitialSpawn" )
    hook.Remove( "PlayerDisconnected", "UTimeDisconnect" )
end

timer.Simple( 5, CFCTime.Utime.deleteUtimeHooks )


local plyMeta = FindMetaTable( "Player" )

-- TODO cfc_time should implement all the UTime getters
function plyMeta:GetUTime()
    return self:GetNWFloat( "TotalUTime" )
end

function plyMeta:SetUTime( num )
    self:SetNWFloat( "TotalUTime", num )
end

function plyMeta:GetUTimeStart()
    return self:GetNWFloat( "UTimeStart" )
end

function plyMeta:SetUTimeStart( num )
    self:SetNWFloat( "UTimeStart", num )
end

function plyMeta:GetUTimeSessionTime()
    return CurTime() - self:GetUTimeStart()
end

function plyMeta:GetUTimeTotalTime()
    return self:GetUTime() + CurTime() - self:GetUTimeStart()
end
