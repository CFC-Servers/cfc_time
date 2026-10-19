local plyMeta = FindMetaTable( "Player" )

-- GetFirstJoin returns the unix timestamp of the player's first join, or nil if it hasn't loaded yet
function plyMeta:GetFirstJoin()
    local firstJoin = self:GetNW2Int( "CFC_Time_FirstJoin", 0 )
    if firstJoin == 0 then return nil end

    return firstJoin
end
