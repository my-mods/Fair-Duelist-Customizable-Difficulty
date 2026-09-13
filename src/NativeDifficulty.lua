-- Confirmed vanilla difficulty changes reset the absolute balance values. MIT.
-- Verified native signatures: Steam build 25232147, RebelSettings.
local M = {}
function M.new(api, directory, report)
    local Config=api.dofile(directory..'Config.lua')
    local Store=api.dofile(directory..'ConfigStore.lua')
    local bridge={}
    local prefix='/Script/RebelSettings.RebelGameUserSettings:'
    local registered, factory, binding, preview, confirmation, queued = {},nil,nil,nil,nil,nil
    local function unwrap(v)
        if type(v)=='number' or type(v)=='boolean' then return v end
        return v and v:get()
    end
    local function valid(o) return o and o:IsValid() end
    local function levels(settings)
        local rpg, action={},{}
        assert(settings:GetSettingAsDifficulty(69,rpg) and settings:GetSettingAsDifficulty(70,action),'Cannot read current difficulty')
        local r,a=rpg.OutDifficulty,action.OutDifficulty
        assert(type(r)=='number' and r%1==0 and r>=0 and r<=3 and type(a)=='number' and a%1==0 and a>=0 and a<=3,'Invalid current difficulty')
        return r,a
    end
    local function settingsObject(window)
        if not valid(factory) then
            -- Cache absence within each finite startup/menu readiness window.
            assert(not window or not window.lookup, 'Game settings factory unavailable')
            if window then window.lookup=true end
            factory=api.StaticFindObject('/Script/RebelSettings.Default__RebelGameUserSettings')
        end
        assert(valid(factory),'Game settings factory unavailable')
        local settings=factory:Get(); assert(valid(settings),'Game settings unavailable')
        return settings
    end
    function bridge.observe()
        return levels(settingsObject())
    end
    function bridge.prepareSettings()
        -- Only fresh installs enter this path. Never read game objects in a
        -- construction callback or create placeholder balance preferences.
        local done,window,reported=false,nil,false
        local function wake()
            if done then return end
            if window then window.lookup=false; return end
            local job={attempts=0}
            window=job
            local function step()
                job.attempts=job.attempts+1
                local ok,r,a=pcall(function()
                    local settings=settingsObject(job)
                    assert(not settings:IsSettingUnconfirmed(69) and not settings:IsSettingUnconfirmed(70),
                        'Waiting for confirmed difficulty settings')
                    return levels(settings)
                end)
                if not ok then
                    if job.attempts<40 then api.ExecuteInGameThreadWithDelay(250,step); return end
                    window=nil
                    if not reported then
                        reported=true
                        report('Initial settings deferred until the main menu or save load: '..tostring(r))
                    end
                    return
                end
                -- Read/write the INI once, after readiness. A file created by
                -- a save load or another writer meanwhile takes precedence.
                done=true; window=nil
                local saved,cfg,path,original=pcall(Store.load,directory,Config,function()
                    local initial=Config.defaults()
                    Config.preset(initial,r,'RPG'); Config.preset(initial,a,'Action')
                    return initial
                end)
                if not saved then report('Initial settings creation failed: '..tostring(cfg))
                elseif original then
                    if FairDuelistLiveSettings then FairDuelistLiveSettings.seed(cfg) end
                    if cfg.debugLogging==1 then
                    report(string.format('Menu settings ready; attempts=%d settings=%s',job.attempts,path))
                    end
                end
            end
            api.ExecuteInGameThreadWithDelay(16,step)
        end
        -- Main menu creation also recovers a startup window that exhausted
        -- before engine settings were available. Event bursts share one job.
        local ok,err=pcall(api.NotifyOnNewObject,
            '/Game/_Dawnwalker/UI/_Unified/MainMenu/WBP_MainMenu.WBP_MainMenu_C',wake)
        if not ok then report('Main menu settings recovery unavailable: '..tostring(err)) end
        wake()
    end
    function bridge.attach(callback)
        binding=callback
        return function() if binding==callback then binding=nil end end
    end
    local function enqueue(settings,rpg,action)
        if queued then
            if queued.settings:GetAddress()~=settings:GetAddress() then queued.settings=settings; queued.rpg=false; queued.action=false end
            queued.rpg=queued.rpg or rpg; queued.action=queued.action or action
            return
        end
        queued={settings=settings,rpg=rpg,action=action}
        api.ExecuteInGameThreadWithDelay(16,function()
            local job=queued; queued=nil
            local ok,err=pcall(function()
                if not valid(job.settings) then return end
                local r,a=levels(job.settings)
                local cfg,path,original=Store.load(directory,Config,function()
                    local initial=Config.defaults()
                    Config.preset(initial,r,'RPG'); Config.preset(initial,a,'Action')
                    return initial
                end)
                if not original then error('Cannot reset invalid settings: '..path) end
                if job.rpg then Config.preset(cfg,r,'RPG') end
                if job.action then Config.preset(cfg,a,'Action') end
                local saved,se=Store.save(directory,Config,cfg,original)
                assert(saved,se)
                if FairDuelistLiveSettings then FairDuelistLiveSettings.commit(cfg) end
                if binding then binding(cfg,r,a) end
                if cfg.debugLogging==1 then report('Vanilla difficulty confirmed; saved '..Config.names[cfg.difficultyPreset+1]..' balance') end
            end)
            if not ok then report('Difficulty reset failed: '..tostring(err)) end
        end)
    end
    local function hook(name,pre,post)
        local a,b=api.RegisterHook(prefix..name,pre,post)
        assert(a and b,'Hook registration failed: '..name)
        registered[#registered+1]={prefix..name,a,b}
    end
    local ok,err=pcall(function()
        hook('PreviewDifficultyPreset',function() end,function(context,_,result)
            if unwrap(result)==true then preview=unwrap(context) end
        end)
        hook('ConfirmSettings',function(context)
            local settings=unwrap(context)
            confirmation=nil
            if not valid(settings) then return end
            local same=valid(preview) and preview:GetAddress()==settings:GetAddress()
            local rpg=same or settings:IsSettingUnconfirmed(69)
            local action=same or settings:IsSettingUnconfirmed(70)
            if rpg or action then confirmation={settings=settings,rpg=rpg,action=action} end
        end,function(context,_,result)
            local request=confirmation; confirmation=nil
            if unwrap(result)~=true then return end
            preview=nil
            if request then
                local settings=unwrap(context)
                if valid(settings) and settings:GetAddress()==request.settings:GetAddress() then enqueue(settings,request.rpg,request.action) end
            end
        end)
        for _,name in ipairs({'ResetUnconfirmedSettings','ResetUnconfirmedSettingsFromSet','ResetUnconfirmedSetting'}) do
            hook(name,function() preview=nil; confirmation=nil end,function() end)
        end
    end)
    if not ok then
        for _,h in ipairs(registered) do pcall(api.UnregisterHook,table.unpack(h)) end
        error(err)
    end
    return bridge
end
return M
