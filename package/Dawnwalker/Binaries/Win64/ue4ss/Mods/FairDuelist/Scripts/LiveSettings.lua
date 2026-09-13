-- MIT. Persistent menu subscription; no work is performed when this module loads.
local M={}
function M.new(directory, report)
    local Adapter=dofile(directory..'UE4SSDawnwalkerSettings.lua')
    local schema=dofile(directory..'SettingsSchema.lua')
    local Config=dofile(directory..'Config.lua')
    local live=Adapter.new({modId="oOCamilleOo_FairDuelist",schema=schema,report=report,
        derive=function(values) values.difficultyPreset=Config.classify(values) end,
        ids={
        ["enabled"]="enabled",
        ["enemyHealthPercent"]="enemyHealthPercent",
        ["enemyDamagePercent"]="enemyDamagePercent",
        ["staminaCostPercent"]="staminaCostPercent",
        ["attackDelayPercent"]="attackDelayPercent",
        ["lowHealthAttackDelayPercent"]="lowHealthAttackDelayPercent",
        ["rangedAttackDelayPercent"]="rangedAttackDelayPercent",
        ["attackDuringBlock"]="attackDuringBlock",
        ["debugLogging"]="debugLogging"
        }})
    live.start(function(id,callback)
        return dofile(directory..'dmm_api.lua').subscribe(id,callback)
    end)
    return live
end
return M
