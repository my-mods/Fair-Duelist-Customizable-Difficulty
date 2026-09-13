# Fair Duelist - Customizable Difficulty

[Download the Vortex archive](https://github.com/my-mods/Fair-Duelist-Customizable-Difficulty/raw/refs/heads/main/Fair-Duelist-Customizable-Difficulty.zip)

Customize enemy health, damage, combat stamina costs and enemy attack delays. Start from Story, Fair, Challenging or Duelist, then adjust individual values. You can use Mod Setting Menu or edit settings.ini yourself.

**Requirements**

- **Required: [UE4SS for BoD](https://www.nexusmods.com/thebloodofdawnwalker/mods/283).** Install a version compatible with your game build. This version of Fair Duelist uses Lua for all balance changes.
- Required: [Mod Setting Menu 1.0.6 or later](https://www.nexusmods.com/thebloodofdawnwalker/mods/271).


**Default values and what the percentages mean**

Your initial balance values match the game's selected RPG and Action difficulties. If those difficulties differ, their respective values are combined. Adjust the values to your liking, press Apply to save and use your changes.

**100%** means the unscaled game value, **50%** means half, and **150%** means one and a half times. These percentages are absolute, not additional multipliers on top of the selected difficulty. All six percentage settings accept values from **0 to 500**. Enter 75 for 75%, not 0.75 or 75%.

The six balance values are: **enemy health / enemy damage / combat stamina cost / normal attack delay / low-health attack delay / ranged attack delay**.

- **Story:** health 50%, damage 40%, stamina cost 50%; normal, low-health and ranged attack delays 200%. Attacks while another enemy blocks: Off.
- **Fair:** health 100%, damage 100%, stamina cost 100%; normal delay 140%, low-health delay 120%, ranged delay 140%. Attacks while another enemy blocks: Off.
- **Challenging:** health 100%, damage 130%, stamina cost 150%; normal delay 120%, low-health delay 100%, ranged delay 120%. Attacks while another enemy blocks: On.
- **Duelist:** health 90%, damage 160%, stamina cost 175%; normal delay 100%, low-health delay 60%, ranged delay 100%. Attacks while another enemy blocks: On.


The balance override starts On and Logging starts Off. **Reset in Mod Settings uses the Duelist values above.** Outdated or invalid settings files also reset to those defaults.

Lower health means enemies take fewer hits; lower damage means you take less damage; lower stamina cost makes combat actions cheaper. **Lower attack-delay percentages let enemies attack more frequently; higher values give longer waits.** Low-health and ranged delays control those specific attack cooldowns. These settings do not change attack animation speed or parry timing. The coordinated-attack switch allows an enemy to attack while another enemy is reacting to a block.

**Editing the settings file**

- Close the game before editing settings.ini.
- Open the game's installation folder. In Steam, right-click the game, then choose Manage > Browse local files.
- Open the file below with Notepad. Back it up before editing.


```ini
Dawnwalker\Binaries\Win64\ue4ss\Mods\FairDuelist\settings.ini
```

Edit the existing values under **[Settings]**. Keep every generated key and the section heading. Do not edit mod_settings.ini, the files in Scripts, or the old %LOCALAPPDATA%\Dawnwalker\Saved\Config\FairDuelist.ini; that old INI is no longer read.

This is a complete **Duelist-default example**; your generated numbers may differ because they start from your selected game difficulties. Change only the values you want in your existing file:

```ini
[Settings]
settingsVersion = 2
enabled = 1
difficultyPreset = 3
enemyHealthPercent = 90
enemyDamagePercent = 160
staminaCostPercent = 175
attackDelayPercent = 100
lowHealthAttackDelayPercent = 60
rangedAttackDelayPercent = 100
attackDuringBlock = 1
debugLogging = 0
```


Keep settingsVersion at 2. Leave the generated difficultyPreset line in place; changing that number does not select a preset. Choose presets through the game's own difficulty settings. For the three switches, 1 means On and 0 means Off. Setting enabled to 0 disables the custom balance override. Leave debugLogging at 0 for normal play. Decimal percentages such as 73.25 are accepted.

**Example: shorter fights with Fair damage, stamina costs and attack delays.** Set enemyHealthPercent to 75, enemyDamagePercent and staminaCostPercent to 100, attackDelayPercent and rangedAttackDelayPercent to 140, lowHealthAttackDelayPercent to 120, and attackDuringBlock to 0. Keep enabled at 1. This gives enemies 25% less health than Fair.

**Save the file, restart the game, and load a save to use your changes.** Do not leave values commented out, duplicate keys, or enter values outside their ranges: an obsolete or invalid file is replaced in full with Duelist defaults.

**Change settings with Mod Setting Menu**

From the main menu, open Mod Settings > Fair Duelist - Customizable Difficulty. Adjust the controls, press Apply to save and update gameplay. Percentage sliders move in 5-point steps. Restore discards unapplied changes; Reset loads Duelist defaults. Logging is the final control.

**Choosing another difficulty**

Confirming a difficulty in the game's settings replaces the corresponding custom values in settings.ini. A full preset resets all balance values; RPG Difficulty resets health, damage and stamina costs; Action Difficulty resets attack delays and attacks while another enemy blocks. Canceling an unconfirmed preview preserves your saved values. To customize a new starting preset, confirm it first, then make your edits. Other game options, including indicators and parry settings, remain controlled by the game's difficulty settings.

**Installation**

- **Vortex:** Install Fair-Duelist-Customizable-Difficulty.zip through Vortex, enable it and deploy.
- **Manual:** Copy the archive's Dawnwalker folder into ...\steamapps\common\The Blood of Dawnwalker\, preserving the folder structure.

**Logging**

Logging is the final menu control. Leave it Off for normal play; On writes troubleshooting details to Dawnwalker\Binaries\Win64\ue4ss\UE4SS.log.

**Credits and source**

Original game and difficulty data: Rebel Wolves and the respective rights holders. Balance choices and mod: oOCamilleOo. This is an unofficial mod. Includes pinned MIT-licensed [ue4ss-common](https://github.com/my-mods/ue4ss-common) helpers; no separate shared-library installation is required.
[Source repository](https://github.com/my-mods/Fair-Duelist-Customizable-Difficulty)

## Live settings

Mod Setting Menu 1.0.6 or later is required. Its callback bridge also requires `HookProcessConsoleExec = 1` in `UE4SS-settings.ini`. Manage that loader setting through your Vortex loader configuration; this archive contains no replacement global UE4SS INI.

Settings are prepared when the game starts and are available from the main menu before the first save. Press **Apply** to save and update the active game. Changes made while loading are retained for the next valid player. Restore and Discard leave saved settings unchanged; Reset takes effect after Apply.

Only affected difficulty values are updated, followed by the game's RPG or Action difficulty notification. Confirming a vanilla difficulty choice retains its separate confirmation flow. Disabling the override restores the values it owns.

Logging is the final, sole diagnostic control. It changes immediately; verbose logging is Off by default. Logs are written to `Dawnwalker/Binaries/Win64/ue4ss/UE4SS.log`. Settings are never polled.
