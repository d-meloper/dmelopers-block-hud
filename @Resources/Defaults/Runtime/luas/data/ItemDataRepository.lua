local ItemDataRepository = {}

local loadedRoot = nil
local hotbarData = nil
local inventoryData = nil
local imageAdjustments = nil
local validation = nil
local editorItemService = nil
local validatedUseBottomSlot = nil

local EMPTY_IMAGE_ADJUSTER = {}

function EMPTY_IMAGE_ADJUSTER.GetAdjustments()
    return 0, 0, 0
end

local function logMessage(message)
    SKIN:Bang(string.format('!Log "%s"', tostring(message):gsub('"', "'")))
end

local function loadModule(R, relativePath)
    return dofile(R .. relativePath)
end

local function resetCache(R)
    if loadedRoot == R then
        return
    end

    loadedRoot = R
    hotbarData = nil
    inventoryData = nil
    imageAdjustments = nil
    validation = nil
    editorItemService = nil
    validatedUseBottomSlot = nil
end

local function loadModuleSafely(R, relativePath, sourceName)
    local ok, result = pcall(loadModule, R, relativePath)
    if ok then
        return result
    end

    logMessage(string.format('[ItemDataRepository] failed to load %s: %s', sourceName, tostring(result)))
    return nil
end

local function ensureValidationModule(module)
    if type(module) == 'table' and type(module.Validate) == 'function' then
        return module
    end

    logMessage('[ItemDataRepository] invalid validation module')
    return nil
end

local function ensureEditorItemService(module)
    if type(module) == 'table' and type(module.BuildSourceRecords) == 'function' then
        return module
    end

    logMessage('[ItemDataRepository] invalid editor item service module')
    return nil
end

local function cloneItem(item)
    if not item then
        return nil
    end

    return {
        Image = item.Image,
        ItemName = item.ItemName,
        ExecPath = item.ExecPath,
        x = item.x,
        y = item.y,
        qty = item.qty,
    }
end

local function cloneInfoList(items)
    local result = {}

    for i = 1, #items do
        local cloned = cloneItem(items[i])
        if cloned then
            table.insert(result, cloned)
        end
    end

    return result
end

local function toNumber(value, defaultValue)
    local n = tonumber(value)
    if n == nil then
        return defaultValue
    end
    return n
end

local function getImageAdjustmentKey(imageName)
    local normalized = tostring(imageName or ''):gsub('^%s+', ''):gsub('%s+$', '')
    return normalized:gsub('%.[^%.]+$', '')
end

local function buildImageAdjustments(sections)
    local adjustments = {}

    for imageName, section in pairs(sections or {}) do
        adjustments[imageName] = {
            x = toNumber(section.OffsetX, 0),
            y = toNumber(section.OffsetY, 0),
            s = toNumber(section.SizeOffset, 0),
        }
    end

    return adjustments
end

local function loadDataSources(R)
    resetCache(R)

    if not editorItemService then
        editorItemService = ensureEditorItemService(loadModuleSafely(R, 'Defaults\\Runtime\\luas\\data\\EditorItemService.lua', 'editor item service'))
    end

    if not hotbarData and editorItemService then
        hotbarData = editorItemService.BuildInfoList(editorItemService.BuildSourceRecords(R, 'hotbar', editorItemService.IsDraftOpen(R)))
    end

    if not inventoryData and editorItemService then
        inventoryData = editorItemService.BuildInfoList(editorItemService.BuildSourceRecords(R, 'inventory', editorItemService.IsDraftOpen(R)))
    end

    if not validation then
        validation = ensureValidationModule(loadModuleSafely(R, 'Defaults\\Runtime\\luas\\validation\\ItemDataValidation.lua', 'validation module'))
    end

    return hotbarData or {}, inventoryData or {}, editorItemService
end

local function loadImageAdjuster(R)
    resetCache(R)

    if not editorItemService then
        editorItemService = ensureEditorItemService(loadModuleSafely(R, 'Defaults\\Runtime\\luas\\data\\EditorItemService.lua', 'editor item service'))
    end

    if not imageAdjustments and editorItemService then
        local adjustments = buildImageAdjustments(editorItemService.ReadImageAdjustmentSections(R) or {})
        imageAdjustments = {
            GetAdjustments = function(imageName)
                local target = adjustments[imageName] or adjustments[getImageAdjustmentKey(imageName)]
                if not target then
                    return 0, 0, 0
                end
                return target.x or 0, target.y or 0, target.s or 0
            end
        }
    end

    return imageAdjustments or EMPTY_IMAGE_ADJUSTER
end

local function buildMergedInfos(hotbarInfos, inventoryInfos)
    local infos = {}

    for i = 1, #hotbarInfos do
        local item = hotbarInfos[i]
        local x = item and tonumber(item.x) or nil
        if item and x and x < 10 then
            table.insert(infos, cloneItem(item))
        end
    end

    for i = 1, #inventoryInfos do
        local item = inventoryInfos[i]
        local y = item and tonumber(item.y) or nil
        if item and y and y ~= 1 then
            table.insert(infos, cloneItem(item))
        end
    end

    return infos
end

local function validate(hotbarInfos, inventoryInfos, useBottomSlot)
    if not validation then
        return
    end

    if validatedUseBottomSlot == useBottomSlot then
        return
    end

    validatedUseBottomSlot = useBottomSlot
    validation.Validate({
        hotbar = hotbarInfos,
        inventory = inventoryInfos,
        useBottomSlot = useBottomSlot,
    })
end

function ItemDataRepository.ResetCaches(R)
    loadedRoot = nil
    hotbarData = nil
    inventoryData = nil
    imageAdjustments = nil
    validation = nil
    editorItemService = nil
    validatedUseBottomSlot = nil
    if R and R ~= '' then
        resetCache(R)
    end
end

function ItemDataRepository.GetImageAdjuster(R)
    return loadImageAdjuster(R)
end

function ItemDataRepository.GetActiveUseBottomSlot(R, fallback)
    local _, _, service = loadDataSources(R)
    if service then
        return service.GetUseBottomSlot(R)
    end

    return fallback == true
end

function ItemDataRepository.GetInfos(R, isHotbar, useBottomSlot)
    local hotbarInfos, inventoryInfos, service = loadDataSources(R)
    local activeUseBottomSlot = useBottomSlot
    if service then
        activeUseBottomSlot = service.GetUseBottomSlot(R)
    end

    validate(hotbarInfos, inventoryInfos, activeUseBottomSlot)

    if isHotbar then
        return cloneInfoList(hotbarInfos)
    end
    if activeUseBottomSlot then
        return cloneInfoList(inventoryInfos)
    end
    return buildMergedInfos(hotbarInfos, inventoryInfos)
end

return ItemDataRepository
