AddCSLuaFile()

CFCTime = {}

if SERVER then
    include( "server/sv_init.lua" )
    AddCSLuaFile( "client/cl_init.lua" )
else
    include( "client/cl_init.lua" )
end
