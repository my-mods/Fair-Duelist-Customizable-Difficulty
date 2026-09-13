-- Absolute balance overrides; finite event work with scalar snapshots. MIT.
local dir=assert(debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])'))
local Config=dofile(dir..'Config.lua')
local function readConfig() return Config.load(dir,function()
    local initial=Config.defaults()
    local rpg,action=FairDuelistNative.observe()
    Config.preset(initial,rpg,'RPG'); Config.preset(initial,action,'Action')
    return initial
end) end
local cfg,path=SaveLoadContext.settings,dir..'../settings.ini'
if not cfg then cfg,path=readConfig();if FairDuelistLiveSettings and cfg.settingsVersion then FairDuelistLiveSettings.seed(cfg) end end
local diagnostics=dofile(dir..'UE4SSCommonDiagnostics.lua').new({mutable=true,debugLogging=cfg.debugLogging==1,prefix='[FairDuelist] ',output=function(text) print(text..'\n') end})
local updateSettings
Session.onSettings(function(values,changes)
    if values.enabled~=cfg.enabled then Session.restart();return end
    if values.debugLogging~=cfg.debugLogging then diagnostics.setEnabled(values.debugLogging==1) end
    if updateSettings then updateSettings(values) else cfg=values end
end)
if cfg.enabled~=1 then return end
local assetPath='/Game/_Dawnwalker/Combat/DA_DifficultyConfig.DA_DifficultyConfig'
local asset,combat,pending,resolve,job=nil,nil,false,true,nil
local combatCandidate
local snapshots={}
local rpgLevel,actionLevel
local refreshRPG,refreshAction=false,false
local dirtyFields={}
for _,field in ipairs(Config.fields) do dirtyFields[field.key]=true end
local attempts,queries,writes=0,0,0
local function valid(o) return o and o:IsValid() end
local function sameWorld(o)
    if not valid(o) then return false end
    -- World subsystems are owned directly by their UWorld.
    local world=o:GetOuter()
    return valid(world) and valid(SaveLoadContext.world) and world:GetAddress()==SaveLoadContext.world:GetAddress()
end
local function combatOwner()
    if sameWorld(combat) then return combat end
    queries=queries+1
    combat=FindFirstOf('CombatSubsystem')
    if not sameWorld(combat) then combat=nil end
    return combat
end
local function desired(field)
    if field.boolean then return cfg[field.key]==1 end
    return cfg[field.key]/100
end
local wake
local function begin()
    if resolve or not valid(asset) then
        queries=queries+1; asset=StaticFindObject(assetPath); resolve=false
        if not valid(asset) then return end
        if asset:GetFullName()~='DifficultyConfig '..assetPath then asset=nil; return end
    end
    local owner=asset
    local address=owner:GetAddress()
    local snapshot=snapshots[address]
    if not snapshot or not valid(snapshot.owner) then snapshot={owner=owner,values={}}; snapshots[address]=snapshot end
    local fields={}
    for _,field in ipairs(Config.fields) do if dirtyFields[field.key] then fields[#fields+1]=field end end
    dirtyFields={}
    job={owner=owner,snapshot=snapshot,fields=fields,cursor=1,changedRPG=refreshRPG,changedAction=refreshAction,
        started=cfg.debugLogging==1 and os.clock() or nil}
end
local function step()
    if combatCandidate then
        if sameWorld(combatCandidate) then combat=combatCandidate end
        combatCandidate=nil
    end
    if not job then
        begin()
        if job then wake(false) end
        return -- Asset discovery and native transactions use separate frames.
    end
    if not job then return end
    local current=job
    if not valid(current.owner) then job=nil; return end
    local started=os.clock()
    local processed=false
    -- At most four scalar transactions per callback; stop after 0.5 ms between them.
    for unit=1,4 do
        if unit>1 and os.clock()-started>=0.0005 then break end
        if current.cursor>4*#current.fields then break end
        processed=true
        local index=math.floor((current.cursor-1)/#current.fields)
        local field=current.fields[(current.cursor-1)%#current.fields+1]
        local token=tostring(current.owner:GetAddress())..':'..index..':'..field.field
        local owner=current.owner
        local function get()
            if not valid(owner) then return nil,false end
            return owner[field.map]:Find(index):get()[field.field]
        end
        local function set(value) owner[field.map]:Find(index):get()[field.field]=value end
        local old=get()
        assert(type(old)==(field.boolean and 'boolean' or 'number'),'Unexpected difficulty field: '..field.field)
        if current.snapshot.values[token]==nil then current.snapshot.values[token]=old end
        local target=desired(field)
        if current.rollback then target=current.snapshot.values[token] end
        if Session.change(token,get,set,target) then
            writes=writes+1
            if field.group=='RPG' then current.changedRPG=true else current.changedAction=true end
        end
        current.cursor=current.cursor+1
    end
    if current.cursor<=4*#current.fields then wake(false); return end
    if processed and (current.changedRPG or current.changedAction) then wake(false);return end
    -- Native setters notify existing combat actors; run the two notifications on separate frames.
    if current.changedRPG or current.changedAction then
        local subsystem=combatOwner()
        if subsystem then
            if rpgLevel==nil or actionLevel==nil then rpgLevel,actionLevel=FairDuelistNative.observe() end
            if current.changedRPG then
                subsystem:SetRPGDifficulty(rpgLevel); current.changedRPG=false; refreshRPG=false; wake(false); return
            end
            if current.changedAction then
                subsystem:SetActionDifficulty(actionLevel); current.changedAction=false; refreshAction=false; wake(false); return
            end
        else
            refreshRPG=current.changedRPG; refreshAction=current.changedAction
        end
    end
    if current.rollback then
        for _,field in ipairs(current.fields) do dirtyFields[field.key]=true end
        job=nil; wake(false); return
    end
    if cfg.debugLogging==1 then diagnostics.debug(string.format('Absolute balance applied; preset=%s searches=%d writes=%d elapsed=%.3fs settings=%s',Config.names[cfg.difficultyPreset+1],queries,writes,current.started and os.clock()-current.started or 0,path)) end
    job=nil; attempts=0
end
wake=function(restart,selected)
    if restart then
        if job then for _,field in ipairs(job.fields) do dirtyFields[field.key]=true end end
        if not selected then for _,field in ipairs(Config.fields) do dirtyFields[field.key]=true end end
        job=nil; attempts=0
    end
    if pending then return end
    pending=true
    ExecuteInGameThreadWithDelay(16,function()
        pending=false
        local ok,err=pcall(step)
        if not ok then
            attempts=attempts+1
            if attempts==1 then diagnostics.error('Balance application failed: %s',tostring(err)) end
            if attempts<8 then
                if job then job.rollback=true; job.cursor=1 end
                wake(false)
            else job=nil; diagnostics.error('Balance work stopped after eight failed attempts; waiting for a new load or difficulty event') end
        end
    end)
end
updateSettings=function(values)
    local changed=false
    for _,field in ipairs(Config.fields) do
        if cfg[field.key]~=values[field.key] then dirtyFields[field.key]=true;changed=true end
    end
    cfg=values
    if changed and (asset or pending) then wake(true,true) end
end
local detach=FairDuelistNative.attach(function(values,rpg,action)
    if values.enabled~=cfg.enabled then Session.restart();return end
    if cfg.debugLogging~=values.debugLogging then diagnostics.setEnabled(values.debugLogging==1) end
    updateSettings(values)
    if rpgLevel~=rpg then refreshRPG=true end
    if actionLevel~=action then refreshAction=true end
    rpgLevel,actionLevel=rpg,action
    if refreshRPG or refreshAction then wake(true,true) end
end)
Session.onClose(detach)
-- Session restoration changes asset rows; notify existing actors as well.
-- The session runner yields after each cleanup callback.
Session.onClose(function()
    if sameWorld(combat) and actionLevel~=nil then combat:SetActionDifficulty(actionLevel) end
end)
Session.onClose(function()
    if sameWorld(combat) and rpgLevel~=nil then combat:SetRPGDifficulty(rpgLevel) end
end)
NotifyOnNewObject('/Script/DogwoodStats.DifficultyConfig',function() resolve=true; wake(true) end)
NotifyOnNewObject('/Script/DogwoodCombat.CombatSubsystem',function(object)
    combatCandidate=object; wake(true)
end)
wake(true)
