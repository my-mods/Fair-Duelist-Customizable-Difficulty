-- Absolute balance values. Original code: MIT.
local M = {}
M.fields = {
    {key='enemyHealthPercent', map='RPGDifficulties', field='HealthMultiplier', group='RPG', max=500},
    {key='enemyDamagePercent', map='RPGDifficulties', field='DamageMultiplier', group='RPG', max=500},
    {key='staminaCostPercent', map='RPGDifficulties', field='PlayerCombatStaminaCostsMultiplier', group='RPG', max=500},
    {key='attackDelayPercent', map='ActionDifficulties', field='HelperTicketCooldownMultiplier', group='Action', max=500},
    {key='lowHealthAttackDelayPercent', map='ActionDifficulties', field='LowHealthHelperTicketCooldownMultiplier', group='Action', max=500},
    {key='rangedAttackDelayPercent', map='ActionDifficulties', field='HelperRangedAttackCooldownMultiplier', group='Action', max=500},
    {key='attackDuringBlock', map='ActionDifficulties', field='bAllowAttackingWhileAnotherNPCIsInBlockReaction', group='Action', boolean=true},
}
M.names = {'Story','Fair','Challenging','Duelist','Custom'}
-- Stock DA_DifficultyConfig, Steam build 25232147. Percentages of unscaled values.
M.presets = {
    {50,40,50,200,200,200,0},
    {100,100,100,140,120,140,0},
    {100,130,150,120,100,120,1},
    {90,160,175,100,60,100,1},
}
function M.preset(values, id, group)
    local row = assert(M.presets[id+1], 'Unknown difficulty preset')
    for i, field in ipairs(M.fields) do
        if not group or group == field.group then values[field.key] = row[i] end
    end
    values.difficultyPreset = M.classify(values)
    return values
end
function M.classify(values)
    for id, row in ipairs(M.presets) do
        local same = true
        for i, field in ipairs(M.fields) do
            local value = values[field.key]
            if type(value)~='number' or math.abs(value-row[i])>0.000001 then same=false; break end
        end
        if same then return id-1 end
    end
    return 4
end
function M.defaults()
    return M.preset({settingsVersion=2,enabled=1,logLevel=2},3)
end
function M.load(directory, initial)
    return dofile(directory .. 'ConfigStore.lua').load(directory, M, initial)
end
return M
