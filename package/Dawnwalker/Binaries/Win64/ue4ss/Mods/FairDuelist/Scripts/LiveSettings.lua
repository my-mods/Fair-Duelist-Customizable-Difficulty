-- MIT. Persistent menu subscription; no work is performed when this module loads.
local M={}
function M.new(directory, report)
    local Adapter=dofile(directory..'UE4SSDawnwalkerSettings.lua')
    local schema=dofile(directory..'SettingsSchema.lua')
    local Config=dofile(directory..'Config.lua')
    local live=Adapter.new({modId="oOCamilleOo_FairDuelist",schema=schema,report=report,
        derive=function(values) values.difficultyPreset=Config.classify(values);require('ModLog').setLevel(values.logLevel) end,
        ids={
        ["enabled"]="enabled",
        ["enemyHealthPercent"]="enemyHealthPercent",
        ["enemyDamagePercent"]="enemyDamagePercent",
        ["staminaCostPercent"]="staminaCostPercent",
        ["attackDelayPercent"]="attackDelayPercent",
        ["lowHealthAttackDelayPercent"]="lowHealthAttackDelayPercent",
        ["rangedAttackDelayPercent"]="rangedAttackDelayPercent",
        ["attackDuringBlock"]="attackDuringBlock",
        ["logLevel"]="logLevel"
        }})
    live.start(function(id,callback)
        return require('ModLog').subscribe(directory,id,callback)
    end)
    return live
end
return M
