-- Load the sv_init.lua from all subfolders, or the files directly if they're alone

require( "playerload" )
CFCTime.includeModules( "server", "sv_init.lua" )
