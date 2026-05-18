local ItemInfosHolder = {}

local Infos = nil
local loadedEssentials = false
local DataRepository = nil
local lastLanguageCode = nil

local function CurrentLanguageCode()
    local value = tostring(SKIN:GetVariable('LanguageCode', 'ko-KR') or ''):match('^%s*(.-)%s*$')
    if value == 'en-US' then
        return 'en-US'
    end
    return 'ko-KR'
end

local function GetSkinValue(name)
    return _G.DMeloper.EvalNumber(SKIN:GetVariable(name)) or 0
end

function ItemInfosHolder.Initialize(R, IsHotbar, UseBottomSlot)
    if not DataRepository then
        DataRepository = dofile(R .. 'Defaults\\Runtime\\luas\\data\\ItemDataRepository.lua')
    end

    return DataRepository.GetInfos(R, IsHotbar, UseBottomSlot)
end

function LoadEssentials()
    if loadedEssentials then return end
    loadedEssentials = true

    R = SKIN:GetVariable('@')

    dofile(R .. 'Defaults\\Runtime\\luas\\DMeloper.lua')
    DataRepository = dofile(R .. 'Defaults\\Runtime\\luas\\data\\ItemDataRepository.lua')

    local IsHotbar = GetSkinValue('IsHotbar') == 1
    local UseBottomSlot = DataRepository.GetActiveUseBottomSlot(R, GetSkinValue('UseInventoryBottomRow') == 1)

    Infos = ItemInfosHolder.Initialize(R, IsHotbar, UseBottomSlot)
    lastLanguageCode = CurrentLanguageCode()
end

function ItemInfosHolder.RefreshInfos()
    LoadEssentials()
    if DataRepository and type(DataRepository.ResetCaches) == 'function' then
        DataRepository.ResetCaches(R)
    end
    local IsHotbar = GetSkinValue('IsHotbar') == 1
    local UseBottomSlot = DataRepository.GetActiveUseBottomSlot(R, GetSkinValue('UseInventoryBottomRow') == 1)
    Infos = ItemInfosHolder.Initialize(R, IsHotbar, UseBottomSlot)
    lastLanguageCode = CurrentLanguageCode()
    return Infos
end

function ItemInfosHolder.GetInfos()
    LoadEssentials()
    if lastLanguageCode ~= CurrentLanguageCode() then
        ItemInfosHolder.RefreshInfos()
    end
    return Infos
end

function ItemInfosHolder.GetInfo(x, y)
    LoadEssentials()
    if lastLanguageCode ~= CurrentLanguageCode() then
        ItemInfosHolder.RefreshInfos()
    end
    for i, item in ipairs(Infos) do
        if item.x == x and item.y == y then
            return item
        end
    end
    return nil
end

return ItemInfosHolder
