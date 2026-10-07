-- Absolute Mod Setting Menu storage. Invalid or outdated files reset to defaults. MIT.
local M = {}
-- Accept only the previous absolute ranges when upgrading to the 500% cap.
local previousMaximum = {
    enemyDamagePercent=800, staminaCostPercent=875,
    attackDelayPercent=2000, lowHealthAttackDelayPercent=2000, rangedAttackDelayPercent=2000,
}
local rangeBackup = '.before-500-percent'
local function cappedPreferences(Store, File, text, schema, Config)
    local previous = {}
    for i, setting in ipairs(schema) do
        local copy = {}; for key, value in pairs(setting) do copy[key]=value end
        copy.max = previousMaximum[setting.key] or copy.max
        previous[i]=copy
    end
    local values = Store.parse(text, previous)
    if not values then return nil end
    local changed = {}
    for _, setting in ipairs(schema) do
        if setting.max and values[setting.key]>setting.max then
            values[setting.key]=setting.max
            changed[#changed+1]=setting
        end
    end
    if #changed==0 then return nil end
    values.difficultyPreset=Config.classify(values)
    for _, setting in ipairs(schema) do
        if setting.key=='difficultyPreset' then changed[#changed+1]=setting; break end
    end
    return values, File.render(text, changed, values), #changed-1
end
function M.load(directory, Config, initial)
    local Store=dofile(directory..'SettingsStore.lua')
    local originalParse=Store.parse
    Store.parse=function(text,schema) return originalParse(require('LogSettings').validation(text),schema) end
    local File=dofile(directory..'SettingsFile.lua')
    local schema=dofile(directory..'SettingsSchema.lua')
    local path=Store.path(directory)
    local text,err,code=Store.read(path)
    local function reject(e) require('ModLog').error('Settings rejected: '..tostring(e)); return {enabled=0},path end
    if text then
        local completion={{key='logLevel',values={0,1,2,3,4},default=2}}
        if Store.parse(text,{{key='settingsVersion',values={2}}}) then
            completion={}
            for _,row in ipairs(schema) do
                local copy={};for k,v in pairs(row) do copy[k]=v end
                copy.max=previousMaximum[row.key] or copy.max
                completion[#completion+1]=copy
            end
        end
        local _,loggingError,updated=require('LogSettings').complete(text,completion)
        if not updated then return reject(loggingError) end
        local saved,saveError=require('LogSettings').replace(path,text,updated)
        if not saved then return reject(saveError) end
        text=updated
        local current,e=Store.parse(text,schema)
        if current then current.difficultyPreset=Config.classify(current); return current,path,text end
        local capped,updated,count=cappedPreferences(Store,File,text,schema,Config)
        if capped then
            local checked,ce=Store.parse(updated,schema)
            if not checked then return reject(ce) end
            local ok,me=File.replace(Store,path,text,updated,rangeBackup,true)
            if not ok then return reject(me) end
            if capped.logLevel==4 then
                require('ModLog').debug('[FairDuelist] Capped '..count..' saved percentages at 500%; original retained at '..path..rangeBackup..'\n')
            end
            return capped,path,updated
        end
        local cfg=Config.defaults()
        local updated=File.render('',schema,cfg)
        local checked,ce=Store.parse(updated,schema)
        if not checked then return reject(ce) end
        local ok,me=File.replace(Store,path,text,updated,'.absolute-write.backup',false)
        if not ok then return reject(me) end
        return cfg,path,updated
    end
    if code~=2 then return reject(err) end
    -- A previous interrupted conversion must never be treated as a fresh install.
    for _,suffix in ipairs({'.absolute-v2.backup','.absolute-write.backup',rangeBackup,rangeBackup..'.new'}) do
        local backup,be,bc=Store.read(path..suffix)
        if backup or bc~=2 then return reject('Recover '..path..suffix..': '..tostring(be or '')) end
    end
    local values,e=Store.load(directory,schema,function()
        return initial and initial() or Config.defaults()
    end)
    if not values then return reject(e) end
    values.difficultyPreset=Config.classify(values)
    return values,path,Store.read(path)
end
-- Make existing preferences readable by the main-menu UI before a save loads.
-- Fresh installs are initialized separately once native settings are readable.
function M.prepare(directory, Config)
    local Store=dofile(directory..'SettingsStore.lua')
    local originalParse=Store.parse
    Store.parse=function(text,schema) return originalParse(require('LogSettings').validation(text),schema) end
    local text,err,code=Store.read(Store.path(directory))
    if text then return M.load(directory, Config) end
    if code~=2 then error(err or 'Cannot read settings') end
end
function M.save(directory, Config, values, expected)
    local Store=dofile(directory..'SettingsStore.lua')
    local originalParse=Store.parse
    Store.parse=function(text,schema) return originalParse(require('LogSettings').validation(text),schema) end
    local File=dofile(directory..'SettingsFile.lua')
    local schema=dofile(directory..'SettingsSchema.lua')
    local path=Store.path(directory)
    local text,err=Store.read(path)
    if not text then return nil,err end
    if expected and text~=expected then return nil,'Settings changed externally; reopen the menu' end
    local parsed,e=Store.parse(text,schema)
    if not parsed then return nil,e end
    values.difficultyPreset=Config.classify(values)
    local updated=File.render(text,schema,values)
    local valid,ve=Store.parse(updated,schema)
    if not valid then return nil,ve end
    return File.replace(Store,path,text,updated,'.absolute-write.backup',false)
end
return M
