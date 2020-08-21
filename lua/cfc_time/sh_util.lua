-- Load the *_init.lua from all subfolders, or the files directly if they're alone
-- TODO: Move to own library

local logger = CFCTime.Logger

function CFCTime.includeModules( moduleDir, initFile )
    logger:info( "Loading " .. moduleDir .. " modules..." )

    local preDirectory = "cfc_time/" .. moduleDir .. "/"

    local _, directories = file.Find( preDirectory .. "*", "LUA" )

    for _, directory in pairs( directories ) do
        local files = file.Find( preDirectory .. directory .. "/*", "LUA" )

        local filePath

        if #files == 1 then
            filePath = preDirectory .. directory .. "/" .. files[1]
        else
            for _, fileName in pairs( files ) do
                if fileName == initFile then
                    filePath = preDirectory .. directory .. "/" .. files[1]
                end
            end

            if not filePath then
                logger:error( "Module " .. directory .. " has multiple files but no " .. initFile )
            end
        end

        if filePath then
            include( filePath )
            logger:info( "Loading " .. moduleDir .. " module: " .. directory )
        end
    end

    logger:info( "Finished loading modules" )
end

function CFCTime.addCSModuleFiles( moduleDir )
    local preDirectory = "cfc_time/" .. moduleDir .. "/"

    local _, directories = file.Find( preDirectory .. "*", "LUA" )

    for _, directory in pairs( directories ) do
        local files = file.Find( preDirectory .. directory .. "/*", "LUA" )

        for _, fileName in pairs( files ) do
            AddCSLuaFile( preDirectory .. directory .. "/" .. fileName )
        end
    end
end
