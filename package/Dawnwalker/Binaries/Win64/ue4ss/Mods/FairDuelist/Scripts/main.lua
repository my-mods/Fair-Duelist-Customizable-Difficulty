-- Migrate existing preferences for the menu; gameplay snapshots wait for save load.
local directory = assert(debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])'))
local function report(message) print('[Save Settings] '..message..'\n') end
local prepared, preferences = pcall(function()
    local Config = dofile(directory..'Config.lua')
    return dofile(directory..'ConfigStore.lua').prepare(directory, Config)
end)
if not prepared then report('Settings preparation failed: '..tostring(preferences)) end
FairDuelistLiveSettings=dofile(directory..'LiveSettings.lua').new(directory,report)
if prepared and preferences and preferences.settingsVersion then FairDuelistLiveSettings.seed(preferences) end
local session = dofile(directory..'UE4SSCommonSession.lua').new(_G, directory, report,{settings=FairDuelistLiveSettings,loadSettings=function() return dofile(directory..'Config.lua').load(directory) end})
local ok, err = pcall(function()
    FairDuelistNative = dofile(directory..'NativeDifficulty.lua').new(_G, directory, report)
    dofile(directory..'UE4SSDawnwalkerSaveLoad.lua').start(_G, session, directory..'Gameplay.lua', report)
    if prepared and not preferences then FairDuelistNative.prepareSettings() end
end)
if not ok then report('Difficulty integration unavailable: '..tostring(err)) end
