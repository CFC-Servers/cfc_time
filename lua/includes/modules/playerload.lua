-- https://github.com/CFC-Servers/gm_playerload

local loadQueue = {}

hook.Add( "PlayerInitialSpawn", "GM_FullLoadSetup", function(ply)
    loadQueue[ply] = true
end )

hook.Add( "SetupMove", "GM_FullLoadTrigger", function( ply, _, cmd )
    if not loadQueue[ply] then return end
    if cmd:IsForced() then return end

    loadQueue[ply] = nil
    hook.Run( "PlayerFullLoad", ply )
end )
