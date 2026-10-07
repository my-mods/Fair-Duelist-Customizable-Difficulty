-- Preserve unrelated keys/comments and use a verified Windows transaction. MIT.
local M = {}
function M.render(text, schema, values)
    local wanted, written, section = {}, {}, ''
    for _, setting in ipairs(schema) do wanted[setting.key] = string.format('%.17g', assert(values[setting.key])) end
    local result = text:gsub('[^\r\n]+', function(line)
        local clean = line:gsub('^\239\187\191',''):gsub('[;#].*$','')
        local heading = clean:match('^%s*%[([^%]]+)%]%s*$')
        if heading then section = heading end
        local key = clean:match('^%s*([%w_]+)%s*=')
        if section=='Settings' and wanted[key] then
            assert(not written[key], 'Duplicate setting: '..key)
            written[key]=true
            return (line:match('^%s*') or '')..key..' = '..wanted[key]..' '..(line:match('[;#].*$') or '')
        end
        return line
    end)
    local missing = {}
    for _, setting in ipairs(schema) do
        if not written[setting.key] then missing[#missing+1]=setting.key..' = '..wanted[setting.key] end
    end
    if #missing>0 then
        local injected=false
        result=result:gsub('([^\r\n]+)(\r?\n)',function(line, newline)
            if not injected and line:gsub('^\239\187\191',''):match('^%s*%[Settings%]%s*$') then
                injected=true; return line..newline..table.concat(missing,newline)..newline
            end
            return line..newline
        end)
        if not injected then result=result..'\n[Settings]\n'..table.concat(missing,'\n')..'\n' end
    end
    return result
end
function M.replace(store, path, original, updated, backupSuffix, retainBackup)
    if original==updated then return true end
    local backup, tmp = path..backupSuffix, path..backupSuffix..'.new'
    for _, name in ipairs({backup,tmp}) do
        local data, err, code = store.read(name)
        if data or code~=2 then return nil, 'Recover existing transaction file: '..name..': '..tostring(err or '') end
    end
    local ready, err = store.create(tmp, updated)
    if not ready then return nil, err end
    if store.read(tmp)~=updated or store.read(path)~=original then os.remove(tmp); return nil, 'Settings changed during transaction' end
    local saved, se=os.rename(path,backup)
    if not saved then os.remove(tmp); return nil,se end
    local ok, ie
    if store.read(backup)==original then ok,ie=os.rename(tmp,path) else ie='Settings changed during backup' end
    if not ok then
        local restored,re=os.rename(backup,path)
        if restored then os.remove(tmp) end
        return nil,tostring(ie)..(restored and '' or '; restore '..backup..': '..tostring(re))
    end
    if store.read(path)~=updated then return nil,'Cannot verify settings; original retained at '..backup end
    if not retainBackup then
        local removed,re=os.remove(backup)
        if not removed then require('ModLog').warning('Saved settings; could not remove transaction backup: '..tostring(re)) end
    end
    return true
end
return M
