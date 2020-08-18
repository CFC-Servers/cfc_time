local plyMeta = FindMetaTable( "Player" )

function plyMeta:GetUTime()
    return self:GetNWFloat( "TotalUTime" )
end

function plyMeta:SetUTime( time )
    self:SetNWFloat( "TotalUTime", time )
end

function plyMeta:GetUTimeStart()
    return self:GetNWFloat( "UTimeStart" )
end

function plyMeta:SetUTimeStart( time )
    self:SetNWFloat( "UTimeStart", time )
end

function plyMeta:GetUTimeSessionTime()
    return CurTime() - self:GetUTimeStart()
end

function plyMeta:GetUTimeTotalTime()
    return self:GetUTime() + CurTime() - self:GetUTimeStart()
end

if SERVER then
    hook.Add( "CFC_Time_PlayerInit", "CFC_Time_UtimeCompat", function( ply, initialTime, currentTime )
        ply:SetUTime( initialTime )
        ply:SetUTimeStart( currentTime )
    end )
end
