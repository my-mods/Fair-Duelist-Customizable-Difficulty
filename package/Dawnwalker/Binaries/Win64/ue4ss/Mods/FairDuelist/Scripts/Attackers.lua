-- MIT. Bind only the loaded player's AI board; finite event work, no polling.
local M={}
function M.start(context,Session,initial,Log,onApplied)
    local current=initial
    local pending=false
    local attempts=0
    local library,board
    local missingHelper=false
    local function valid(o)return o and o:IsValid() end
    local function native(address,limit)
        if type(_FDConfigureAttackersV1)~='function' then
            if limit~=0 and not missingHelper then
                missingHelper=true
                Log.error('Attacker limit requires the matching native helper; other balance settings remain active')
            end
            return limit==0
        end
        return _FDConfigureAttackersV1(address,limit,current.logLevel or 2)
    end
    local wake
    local function step()
        pending=false
        if current.maxSimultaneousAttackers==0 then
            if native(0,0) and onApplied then onApplied(0) end
            board=nil;return
        end
        attempts=attempts+1
        local ok,applied=pcall(function()
            local pawn=context.pawn
            if not valid(pawn) or not valid(context.world) or pawn:GetWorld():GetAddress()~=context.world:GetAddress() then return false end
            if not valid(library) then library=StaticFindObject('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary') end
            if not valid(library) then return false end
            local stub=library:GetAIStub(pawn)
            if not valid(stub) or stub:IsPlayer()~=true or stub:IsInitializedAndHasPawn()~=true then return false end
            local actor=stub:GetActor()
            if not valid(actor) or actor:GetAddress()~=pawn:GetAddress() then return false end
            board=stub:GetAIBoard()
            if not valid(board) then return false end
            return native(board:GetAddress(),current.maxSimultaneousAttackers)
        end)
        if ok and applied then
            attempts=0
            if onApplied then onApplied(current.maxSimultaneousAttackers) end
            return
        end
        if attempts<40 then wake(false,250)
        else Log.warning('Attacker limit readiness exhausted; retry on the next load or settings change%s',ok and '' or (': '..tostring(applied))) end
    end
    wake=function(reset,delay)
        if reset then attempts=0 end
        if pending then return end
        pending=true
        ExecuteInGameThreadWithDelay(delay or 16,step)
    end
    local function apply(values)
        local changed=values.maxSimultaneousAttackers~=current.maxSimultaneousAttackers
        local logging=values.logLevel~=current.logLevel
        current=values
        if changed then wake(true)
        elseif logging and valid(board) then native(board:GetAddress(),current.maxSimultaneousAttackers) end
    end
    Session.onClose(function()native(0,0);board=nil end)
    NotifyOnNewObject('/Script/RebelAI.RebelAIBoard',function()
        if current.maxSimultaneousAttackers~=0 then wake(true) end
    end)
    wake(true)
    return apply
end
return M
