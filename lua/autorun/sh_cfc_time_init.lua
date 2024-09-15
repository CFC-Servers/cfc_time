CFCTime = {}

AddCSLuaFile( "cfc_time/shared/config.lua" )
AddCSLuaFile( "cfc_time/shared/utime_compat.lua" )

include( "cfc_time/shared/config.lua" )
include( "cfc_time/shared/utime_compat.lua" )

if SERVER then
    include( "cfc_time/server/storage.lua" )
    include( "cfc_time/server/time_tracking.lua" )
end
