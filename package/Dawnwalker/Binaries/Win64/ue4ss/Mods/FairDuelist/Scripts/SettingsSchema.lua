-- Absolute settings contract. MIT.
return {
    {key="settingsVersion", default=2, values={2}},
    {key="enabled", default=1, values={0,1}},
    {key="difficultyPreset", default=3, values={0,1,2,3,4}},
    {key="enemyHealthPercent", default=90, min=0, max=500},
    {key="enemyDamagePercent", default=160, min=0, max=500},
    {key="staminaCostPercent", default=175, min=0, max=500},
    {key="attackDelayPercent", default=100, min=0, max=500},
    {key="lowHealthAttackDelayPercent", default=60, min=0, max=500},
    {key="rangedAttackDelayPercent", default=100, min=0, max=500},
    {key="attackDuringBlock", default=1, values={0,1}},
    {key="logLevel", default=2, values={0,1,2,3,4}},
}
