local EditorItemService = {}
local RESERVED_INVENTORY_LABEL_VARIABLE = "Loc_Editor_ItemReservedInventory"
local RESERVED_INVENTORY_LABEL_REFERENCE = "#" .. RESERVED_INVENTORY_LABEL_VARIABLE .. "#"

local function hasSkinMethod(api, methodName)
    return api ~= nil and type(api[methodName]) == "function"
end

local skinApi = SKIN
if not hasSkinMethod(skinApi, "GetVariable") then
    skinApi = {
        GetVariable = function(_, _, fallback)
            return fallback or ""
        end,
    }
end
local SKIN = skinApi

local function localize(key, fallback)
    if hasSkinMethod(SKIN, "GetVariable") then
        return SKIN:GetVariable("Loc_" .. tostring(key or ""), fallback or "")
    end
    return fallback or ""
end

local function isEnglishLocale()
    return tostring(SKIN:GetVariable("LanguageCode", "ko-KR") or ""):match("^%s*(.-)%s*$") == "en-US"
end

local function reservedInventoryFallback()
    if isEnglishLocale() then
        return "Inventory"
    end
    return "인벤토리"
end

local function reservedInventoryLabel()
    return localize("Editor_ItemReservedInventory", reservedInventoryFallback())
end

local function locRef(key)
    return "#Loc_" .. tostring(key or "") .. "#"
end

local RESERVED_SLOT10 = {
    Source = "hotbar",
    Section = "Slot10",
    x = 10,
    y = 1,
    ImageKey = "more.png",
    ItemName = reservedInventoryLabel(),
    ExecPath = "_OPEN_INVENTORY_",
    Qty = 0,
    Populated = true,
}

local SPECIAL_ACTION_LABELS = {
    ["_open_inventory_"] = reservedInventoryLabel(),
}

local BUILT_IN_FAVORITES = {
    { Label = locRef("Editor_Favorite_ThisPC"), Action = 'explorer.exe shell:::{20D04FE0-3AEA-1069-A2D8-08002B30309D}' },
    { Label = locRef("Editor_Favorite_RecycleBin"), Action = 'explorer.exe shell:::{645FF040-5081-101B-9F08-00AA002F954E}' },
    { Label = locRef("Editor_Favorite_Shutdown"), Action = 'shutdown -s -t 0' },
    { Label = locRef("Editor_Favorite_Restart"), Action = 'shutdown -r -t 0' },
    { Label = locRef("Editor_Favorite_Desktop"), Action = 'explorer.exe shell:::{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}' },
    { Label = locRef("Editor_Favorite_Downloads"), Action = 'explorer.exe shell:::{374DE290-123F-4565-9164-39C4925E467B}' },
    { Label = locRef("Editor_Favorite_ThisPC"), Action = 'explorer.exe "shell:MyComputerFolder"' },
    { Label = locRef("Editor_Favorite_RecycleBin"), Action = 'explorer.exe "shell:RecycleBinFolder"' },
}

RESERVED_SLOT10.ItemName = reservedInventoryLabel()
SPECIAL_ACTION_LABELS["_open_inventory_"] = reservedInventoryLabel()

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function toNumber(value, defaultValue)
    local numeric = tonumber(trim(value))
    if numeric == nil then
        return defaultValue
    end

    return math.floor(numeric)
end
local VARIABLE_MISSING = "__DMCS_VARIABLE_MISSING__"
local ITEM_KEYS = { "Image", "Label", "Action", "Qty" }
local DRAFT_META_KEYS = {
    "SchemaVersion",
    "Dirty",
    "EditorOpen",
    "HeartbeatClockMs",
    "PickerModalOpen",
    "SelectedSource",
    "SelectedX",
    "SelectedY",
    "SelectedSection",
    "DragSource",
    "DragX",
    "DragY",
    "DragActive",
}
local IMAGE_ADJUSTMENT_KEYS = { "OffsetX", "OffsetY", "SizeOffset" }
local DRAFT_SESSION_HEARTBEAT_INTERVAL_MS = 1000
local DRAFT_SESSION_TIMEOUT_MS = 3000
local SUPPORTED_IMAGE_EXTENSIONS = {
    png = true,
    jpg = true,
    jpeg = true,
    jpe = true,
    bmp = true,
    gif = true,
    tif = true,
    tiff = true,
    ico = true,
    jxr = true,
    wdp = true,
    dds = true,
}

local function getVariable(name, fallback)
    local value = SKIN:GetVariable(name, VARIABLE_MISSING)
    if value == VARIABLE_MISSING then
        return fallback
    end
    return value
end

local function resolveVariableReference(value)
    local reference = trim(value):match("^#([^#]+)#$")
    if reference and reference ~= "" then
        return getVariable(reference, value)
    end
    return value
end

local function isReservedInventoryLabelLiteral(value)
    local text = trim(value)
    if text == "" then
        return false
    end
    if text == RESERVED_INVENTORY_LABEL_REFERENCE or text == RESERVED_INVENTORY_LABEL_VARIABLE then
        return true
    end
    if text == "Inventory" or text == "인벤토리" then
        return true
    end

    local localized = trim(reservedInventoryLabel())
    return localized ~= "" and text == localized
end

local function isReservedInventoryLabelValue(value)
    local text = trim(value)
    if isReservedInventoryLabelLiteral(text) then
        return true
    end

    local resolved = trim(resolveVariableReference(text))
    if resolved ~= text and isReservedInventoryLabelLiteral(resolved) then
        return true
    end

    local secondResolved = trim(resolveVariableReference(resolved))
    return secondResolved ~= resolved and isReservedInventoryLabelLiteral(secondResolved)
end

local function pathEndsWith(path, suffix)
    local normalizedPath = tostring(path or ""):gsub("/", "\\"):lower()
    local normalizedSuffix = tostring(suffix or ""):gsub("/", "\\"):lower()
    return normalizedPath:sub(-#normalizedSuffix) == normalizedSuffix
end

local function getSectionNamesForSource(source)
    local names = {}

    if source == "hotbar" then
        for x = 1, 10 do
            names[#names + 1] = string.format("Slot%02d", x)
        end
    elseif source == "inventory" then
        for y = 1, 4 do
            for x = 1, 9 do
                names[#names + 1] = string.format("SlotX%dY%d", x, y)
            end
        end
    end

    return names
end

local function readItemVariableSection(prefix, sectionName)
    local section = {}
    local found = false

    for _, key in ipairs(ITEM_KEYS) do
        local value = getVariable(prefix .. "_" .. sectionName .. "_" .. key, nil)
        if value ~= nil then
            section[key] = value
            found = true
        end
    end

    if found then
        return section
    end

    return nil
end

local function readSourceVariableSections(prefix, source)
    local sections = {}
    local found = false

    for _, sectionName in ipairs(getSectionNamesForSource(source)) do
        local section = readItemVariableSection(prefix, sectionName)
        if section then
            sections[sectionName] = section
            found = true
        end
    end

    if found then
        return sections
    end

    return nil
end

local function readDraftMetaVariables()
    local variables = {}
    local found = false

    for _, key in ipairs(DRAFT_META_KEYS) do
        local value = getVariable("EditorDraftMeta_" .. key, nil)
        if value ~= nil then
            variables[key] = value
            found = true
        end
    end

    if found then
        return variables
    end

    return nil
end

local function readDraftVariableSections()
    local sections = {}
    local found = false

    local variables = readDraftMetaVariables()
    if variables then
        sections.Variables = variables
        found = true
    end

    for _, source in ipairs({ "hotbar", "inventory" }) do
        local sourceSections = readSourceVariableSections("EditorDraftItem", source)
        if sourceSections then
            for sectionName, section in pairs(sourceSections) do
                sections[sectionName] = section
            end
            found = true
        end
    end

    if found then
        return sections
    end

    return nil
end

local function readIniVariableSubset(content, wantedKeys)
    local variables = {}
    local found = false
    local currentSection = nil

    if type(content) ~= "string" or content == "" then
        return nil
    end

    for rawLine in content:gmatch("[^\r\n]+") do
        local line = trim(rawLine)
        if line ~= "" and not line:match("^;") then
            local sectionName = line:match("^%[(.-)%]$")
            if sectionName and sectionName ~= "" then
                currentSection = trim(sectionName)
            elseif currentSection == "Variables" then
                local key, value = line:match("^([^=]+)=(.*)$")
                if key then
                    key = trim(key)
                    if wantedKeys[key] then
                        variables[key] = trim(value)
                        found = true
                    end
                end
            end
        end
    end

    if found then
        return variables
    end

    return nil
end

local function readInventorySettingsVariableSections()
    local useBottomRow = getVariable("UseInventoryBottomRow", nil)
    if useBottomRow == nil then
        return nil
    end

    return {
        Variables = {
            UseInventoryBottomRow = useBottomRow,
        }
    }
end

local function readImageAdjustmentVariableSections()
    local keys = trim(getVariable("ImageAdjustKeys", ""))
    if keys == "" then
        return nil
    end

    local sections = {}
    for imageKey in keys:gmatch("[^|]+") do
        local section = {}
        local found = false
        for _, key in ipairs(IMAGE_ADJUSTMENT_KEYS) do
            local value = getVariable("ImageAdjust_" .. imageKey .. "_" .. key, nil)
            if value ~= nil then
                section[key] = value
                found = true
            end
        end
        if found then
            sections[imageKey] = section
        end
    end

    return sections
end

local function readVariableSections(path)
    if pathEndsWith(path, "Customs\\Data\\HotbarItems.inc") then
        return readSourceVariableSections("HotbarItem", "hotbar")
    end

    if pathEndsWith(path, "Customs\\Data\\InventoryItems.inc") then
        return readSourceVariableSections("InventoryItem", "inventory")
    end

    if pathEndsWith(path, "Customs\\Data\\EditorDraft.inc") then
        return readDraftVariableSections()
    end


    if pathEndsWith(path, "Customs\\Settings\\Inventory.inc") then
        return readInventorySettingsVariableSections()
    end

    if pathEndsWith(path, "Customs\\Data\\ImageAdjustments.inc") then
        return readImageAdjustmentVariableSections()
    end

    return nil
end

local function encodeUtf8Codepoint(codepoint)
    if codepoint < 0x80 then
        return string.char(codepoint)
    end
    if codepoint < 0x800 then
        local b1 = 0xC0 + math.floor(codepoint / 0x40)
        local b2 = 0x80 + (codepoint % 0x40)
        return string.char(b1, b2)
    end
    local b1 = 0xE0 + math.floor(codepoint / 0x1000)
    local b2 = 0x80 + (math.floor(codepoint / 0x40) % 0x40)
    local b3 = 0x80 + (codepoint % 0x40)
    return string.char(b1, b2, b3)
end

local function decodeUtf16Le(content)
    local chars = {}
    local length = #content
    local index = 1
    while index < length do
        local lo = content:byte(index) or 0
        local hi = content:byte(index + 1) or 0
        local codepoint = lo + (hi * 256)
        if codepoint == 0 then
            break
        end
        chars[#chars + 1] = encodeUtf8Codepoint(codepoint)
        index = index + 2
    end
    return table.concat(chars)
end

local function readTextFileAuto(path)
    local resolved = trim(path)
    if resolved == "" then
        return nil
    end

    local handle = io.open(resolved, "rb")
    if not handle then
        return nil
    end

    local content = handle:read("*a") or ""
    handle:close()

    if content:sub(1, 2) == string.char(0xFF, 0xFE) then
        return decodeUtf16Le(content:sub(3))
    end

    if content:sub(1, 2) == string.char(0xFE, 0xFF) then
        return nil
    end

    if content:sub(1, 3) == string.char(0xEF, 0xBB, 0xBF) then
        content = content:sub(4)
    end

    return content
end

local function parseIniSections(content)
    local sections = {}
    if type(content) ~= "string" or content == "" then
        return sections
    end

    local currentSection = nil
    for rawLine in content:gmatch("[^\r\n]+") do
        local line = trim(rawLine)
        if line ~= "" and not line:match("^;") then
            local sectionName = line:match("^%[(.-)%]$")
            if sectionName and sectionName ~= "" then
                currentSection = trim(sectionName)
                if sections[currentSection] == nil then
                    sections[currentSection] = {}
                end
            elseif currentSection then
                local key, value = line:match("^([^=]+)=(.*)$")
                if key then
                    sections[currentSection][trim(key)] = trim(value)
                end
            end
        end
    end

    return sections
end

local function buildItemSectionsFromVariables(variables, prefix, source)
    local sections = {}
    for _, sectionName in ipairs(getSectionNamesForSource(source)) do
        local section = {}
        local found = false
        for _, key in ipairs(ITEM_KEYS) do
            local value = variables[prefix .. "_" .. sectionName .. "_" .. key]
            if value ~= nil then
                section[key] = value
                found = true
            end
        end
        if found then
            sections[sectionName] = section
        end
    end
    return sections
end

local function buildDraftMetaVariablesFromPrefixedVariables(variables)
    local meta = {}
    local found = false

    for _, key in ipairs(DRAFT_META_KEYS) do
        local value = variables["EditorDraftMeta_" .. key]
        if value ~= nil then
            meta[key] = value
            found = true
        end
    end

    if found then
        return meta
    end

    return nil
end

local function buildDraftItemSectionFromPrefixedVariables(variables, sectionName)
    local section = {}
    local found = false

    for _, key in ipairs(ITEM_KEYS) do
        local value = variables["EditorDraftItem_" .. sectionName .. "_" .. key]
        if value ~= nil then
            section[key] = value
            found = true
        end
    end

    if found then
        return section
    end

    return nil
end

local function buildDraftSectionsFromVariables(variables)
    local sections = {}
    local meta = buildDraftMetaVariablesFromPrefixedVariables(variables)

    if meta then
        sections.Variables = meta
    end

    for _, source in ipairs({ "hotbar", "inventory" }) do
        local sourceSections = buildItemSectionsFromVariables(variables, "EditorDraftItem", source)
        for sectionName, section in pairs(sourceSections) do
            sections[sectionName] = section
        end
    end

    return sections
end

local function buildInventorySettingsSectionsFromVariables(variables)
    local useBottomRow = variables.UseInventoryBottomRow
    if useBottomRow == nil then
        return {}
    end
    return {
        Variables = {
            UseInventoryBottomRow = useBottomRow,
        }
    }
end

local function buildImageAdjustmentSectionsFromVariables(variables)
    local keys = trim(variables.ImageAdjustKeys)
    if keys == "" then
        return {}
    end

    local sections = {}
    for imageKey in keys:gmatch("[^|]+") do
        local section = {}
        local found = false
        for _, key in ipairs(IMAGE_ADJUSTMENT_KEYS) do
            local value = variables["ImageAdjust_" .. imageKey .. "_" .. key]
            if value ~= nil then
                section[key] = value
                found = true
            end
        end
        if found then
            sections[imageKey] = section
        end
    end

    return sections
end

local function cloneSectionMap(sectionMap)
    local cloned = {}
    for sectionName, section in pairs(sectionMap or {}) do
        local clonedSection = {}
        for key, value in pairs(section or {}) do
            clonedSection[key] = value
        end
        cloned[sectionName] = clonedSection
    end
    return cloned
end

local function mergeSectionMaps(baseSections, overlaySections)
    local merged = cloneSectionMap(baseSections)
    for sectionName, section in pairs(overlaySections or {}) do
        local mergedSection = merged[sectionName]
        if mergedSection == nil then
            mergedSection = {}
            merged[sectionName] = mergedSection
        end
        for key, value in pairs(section or {}) do
            mergedSection[key] = value
        end
    end
    return merged
end

local function readFileSections(path)
    local content = readTextFileAuto(path)
    if not content then
        return {}
    end
    local parsed = parseIniSections(content)
    local variables = parsed.Variables or {}

    if pathEndsWith(path, "Customs\\Data\\HotbarItems.inc") then
        return buildItemSectionsFromVariables(variables, "HotbarItem", "hotbar")
    end

    if pathEndsWith(path, "Customs\\Data\\InventoryItems.inc") then
        return buildItemSectionsFromVariables(variables, "InventoryItem", "inventory")
    end

    if pathEndsWith(path, "Customs\\Data\\EditorDraft.inc") then
        return buildDraftSectionsFromVariables(variables)
    end

    if pathEndsWith(path, "Customs\\Settings\\Inventory.inc") then
        return buildInventorySettingsSectionsFromVariables(variables)
    end

    if pathEndsWith(path, "Customs\\Data\\ImageAdjustments.inc") then
        return buildImageAdjustmentSectionsFromVariables(variables)
    end

    return parsed
end


local function ensureTrailingSlash(path)
    if path:match("[/\\]$") then
        return path
    end

    return path .. "\\"
end

local function cloneRecord(record)
    if type(record) ~= "table" then
        return nil
    end

    return {
        Source = record.Source,
        Section = record.Section,
        x = record.x,
        y = record.y,
        ImageKey = record.ImageKey or "",
        ItemName = record.ItemName or "",
        ExecPath = record.ExecPath or "",
        Qty = toNumber(record.Qty, 0),
        Populated = record.Populated == true,
    }
end

local function makeEmptyRecord(source, x, y)
    return {
        Source = source,
        Section = EditorItemService.GetSectionName(source, x, y),
        x = x,
        y = y,
        ImageKey = "",
        ItemName = "",
        ExecPath = "",
        Qty = 0,
        Populated = false,
    }
end

local function readSections(_, path)
    local variableSections = readVariableSections(path)
    if variableSections then
        return variableSections
    end

    return readFileSections(path)
end

local function normalizeSource(source)
    local normalized = trim(source):lower()
    if normalized == "hotbar" or normalized == "inventory" then
        return normalized
    end

    return nil
end

local function getDraftSectionName(source, x, y)
    source = normalizeSource(source)
    x = toNumber(x, nil)
    y = toNumber(y, nil)

    if not source or not x or not y then
        return nil
    end

    if source == "hotbar" then
        return string.format("Slot%02d", x)
    end

    return string.format("SlotX%dY%d", x, y)
end

local function readDraftMetaSections(path)
    local variableSections = readDraftMetaVariables()
    if variableSections then
        return variableSections
    end

    local content = readTextFileAuto(path)
    if not content then
        return nil
    end

    local wantedKeys = {}
    for _, key in ipairs(DRAFT_META_KEYS) do
        wantedKeys["EditorDraftMeta_" .. key] = true
    end

    local variables = readIniVariableSubset(content, wantedKeys)
    if not variables then
        return nil
    end

    return buildDraftMetaVariablesFromPrefixedVariables(variables)
end

local function readDraftSlotSection(R, source, x, y)
    local sectionName = getDraftSectionName(source, x, y)
    if not sectionName then
        return nil
    end

    local variableSection = readItemVariableSection("EditorDraftItem", sectionName)
    if variableSection then
        return variableSection
    end

    local content = readTextFileAuto(EditorItemService.GetPaths(R).Draft)
    if not content then
        return nil
    end

    local wantedKeys = {}
    for _, key in ipairs(ITEM_KEYS) do
        wantedKeys["EditorDraftItem_" .. sectionName .. "_" .. key] = true
    end

    local variables = readIniVariableSubset(content, wantedKeys)
    if not variables then
        return nil
    end

    return buildDraftItemSectionFromPrefixedVariables(variables, sectionName)
end

local function normalizeAction(action)
    if action == "_G.DMeloper.OPEN_INVENTORY_KEY" then
        return "_OPEN_INVENTORY_"
    end

    return trim(action)
end

local function buildDraftMeta(variables)
    variables = variables or {}
    return {
        SchemaVersion = toNumber(variables.SchemaVersion, 2),
        Dirty = trim(variables.Dirty) == "1",
        EditorOpen = trim(variables.EditorOpen) == "1",
        HeartbeatClockMs = toNumber(variables.HeartbeatClockMs, 0),
        PickerModalOpen = trim(variables.PickerModalOpen) == "1",
        SelectedSource = normalizeSource(variables.SelectedSource),
        SelectedX = toNumber(variables.SelectedX, 0),
        SelectedY = toNumber(variables.SelectedY, 0),
        SelectedSection = trim(variables.SelectedSection),
        DragSource = normalizeSource(variables.DragSource),
        DragX = toNumber(variables.DragX, 0),
        DragY = toNumber(variables.DragY, 0),
        DragActive = trim(variables.DragActive) == "1",
    }
end

function EditorItemService.GetPaths(R)
    return {
        HotbarData = R .. "Customs\\Data\\HotbarItems.inc",
        InventoryData = R .. "Customs\\Data\\InventoryItems.inc",
        InventorySettings = R .. "Customs\\Settings\\Inventory.inc",
        Draft = R .. "Customs\\Data\\EditorDraft.inc",
        ProgramPickerCache = R .. "Customs\\Data\\EditorProgramPickerCache.txt",
        ProgramActionLabels = R .. "Customs\\Data\\ProgramActionLabels.txt",
        FavoritesCatalog = R .. "Customs\\Data\\EditorFavoritesCatalog.txt",
        ItemImageDirectory = ensureTrailingSlash(R .. "Customs\\Images\\Items"),
        RuntimeImageDirectory = ensureTrailingSlash(R .. "Defaults\\Runtime\\images"),
    }
end

function EditorItemService.NormalizeSource(source)
    return normalizeSource(source)
end

function EditorItemService.NormalizeAction(action)
    return normalizeAction(action)
end

function EditorItemService.IsReservedHotbarSlot(source, x, y)
    return normalizeSource(source) == "hotbar"
        and toNumber(x, 0) == RESERVED_SLOT10.x
        and toNumber(y, 0) == RESERVED_SLOT10.y
end

function EditorItemService.GetReservedHotbarSlotRecord()
    return cloneRecord(RESERVED_SLOT10)
end

function EditorItemService.GetSourceDataPath(R, source)
    local paths = EditorItemService.GetPaths(R)
    source = normalizeSource(source)

    if source == "hotbar" then
        return paths.HotbarData
    end

    if source == "inventory" then
        return paths.InventoryData
    end

    return nil
end

function EditorItemService.GetSectionName(source, x, y)
    source = normalizeSource(source)
    x = toNumber(x, nil)
    y = toNumber(y, nil)

    if not source or not x or not y then
        return nil
    end

    if source == "hotbar" then
        return string.format("Slot%02d", x)
    end

    return string.format("SlotX%dY%d", x, y)
end

function EditorItemService.GetAllSectionNames(source)
    local names = {}
    source = normalizeSource(source)
    if source == "hotbar" then
        for x = 1, 10 do
            names[#names + 1] = string.format("Slot%02d", x)
        end
    elseif source == "inventory" then
        for y = 1, 4 do
            for x = 1, 9 do
                names[#names + 1] = string.format("SlotX%dY%d", x, y)
            end
        end
    end
    return names
end

function EditorItemService.IsEmptyItemSection(section)
    if type(section) ~= "table" then
        return true
    end

    local qty = toNumber(section.Qty, 0)
    return trim(section.Image) == ""
        and trim(section.Label) == ""
        and normalizeAction(section.Action) == ""
        and qty == 0
end

function EditorItemService.GetCoordBounds(source, useBottomSlot)
    source = normalizeSource(source)

    if source == "hotbar" then
        return {
            XMin = 1,
            XMax = 9,
            YMin = 1,
            YMax = 1,
        }
    end

    if source == "inventory" then
        return {
            XMin = 1,
            XMax = 9,
            YMin = useBottomSlot and 1 or 2,
            YMax = 4,
        }
    end

    return nil
end

function EditorItemService.IsValidCoord(source, x, y, useBottomSlot)
    if EditorItemService.IsReservedHotbarSlot(source, x, y) then
        return false
    end

    local bounds = EditorItemService.GetCoordBounds(source, useBottomSlot)
    x = toNumber(x, nil)
    y = toNumber(y, nil)

    if not bounds or not x or not y then
        return false
    end

    return x >= bounds.XMin and x <= bounds.XMax
        and y >= bounds.YMin and y <= bounds.YMax
end

function EditorItemService.GetPersistedUseBottomSlot(R)
    local sections = readSections(R, EditorItemService.GetPaths(R).InventorySettings)
    local variables = sections.Variables or {}
    return trim(variables.UseInventoryBottomRow) == "1"
end

function EditorItemService.GetUseBottomSlot(R)
    return EditorItemService.GetPersistedUseBottomSlot(R)
end

local function getImageExtension(imageAsset)
    local extension = trim(imageAsset):match("%.([^%.]+)$")
    if not extension then
        return ""
    end

    return extension:lower()
end

local function stripImageExtension(imageAsset)
    local normalized = trim(imageAsset)
    return normalized:gsub("%.[^%.]+$", "")
end

local function splitSegments(value, pattern)
    local segments = {}
    for segment in tostring(value or ""):gmatch(pattern) do
        if segment ~= "" then
            segments[#segments + 1] = segment
        end
    end
    return segments
end

local function humanizeAppToken(value)
    local normalized = trim(value)
    if normalized == "" then
        return ""
    end

    normalized = normalized:gsub("[_%-%+]+", " ")
    normalized = normalized:gsub("([%l%d])([%u])", "%1 %2")
    normalized = normalized:gsub("(%u)(%u%l)", "%1 %2")
    normalized = normalized:gsub("%s+", " ")

    return trim(normalized)
end

local function extractAppsFolderAppId(action)
    local normalized = trim(action):gsub("/", "\\")
    return normalized:match("[Ss][Hh][Ee][Ll][Ll]:[Aa][Pp][Pp][Ss][Ff][Oo][Ll][Dd][Ee][Rr]\\+(.+)$")
end

local function readUtf8TextFile(path)
    local content = readTextFileAuto(path)
    if not content then
        return nil
    end
    return content
end

local lookupCachesByRoot = {}

local function getLookupCache(R)
    local root = trim(R)
    local cache = lookupCachesByRoot[root]
    if cache then
        return cache
    end

    cache = {}
    lookupCachesByRoot[root] = cache
    return cache
end

local function clearLookupCache(R, key)
    local cache = getLookupCache(R)
    cache[key] = nil
end

local function getOrBuildLookupCache(R, key, builder)
    local cache = getLookupCache(R)
    local cached = cache[key]
    if cached ~= nil then
        return cached
    end

    local built = builder()
    cache[key] = built
    return built
end

local function readProgramActionLabels(R)
    return getOrBuildLookupCache(R, "programActionLabels", function()
        if trim(R) == "" then
            return {}
        end

        local path = EditorItemService.GetPaths(R).ProgramActionLabels
        local content = readUtf8TextFile(path)
        if not content then
            return {}
        end

        local labels = {}
        for line in content:gmatch("[^\r\n]+") do
            local actionValue, label = line:match("^([^\t]+)\t(.*)$")
            actionValue = trim(actionValue)
            label = trim(label)
            if actionValue ~= "" and label ~= "" then
                labels[actionValue] = label
            end
        end

        return labels
    end)
end

local function readProgramPickerCacheLabels(R)
    return getOrBuildLookupCache(R, "programPickerLabels", function()
        if trim(R) == "" then
            return {}
        end

        local path = EditorItemService.GetPaths(R).ProgramPickerCache
        local content = readUtf8TextFile(path)
        if not content then
            return {}
        end

        local labels = {}
        for line in content:gmatch("[^\r\n]+") do
            local appId, label = line:match("^([^\t]+)\t(.*)$")
            appId = trim(appId)
            label = trim(label)
            if appId ~= "" and label ~= "" then
                labels[appId] = label
            end
        end

        return labels
    end)
end

local function lookupProgramPickerLabel(R, actionOrAppId)
    local appId = extractAppsFolderAppId(actionOrAppId) or trim(actionOrAppId)
    if appId == "" then
        return nil
    end

    return readProgramPickerCacheLabels(R)[appId]
end

local function readFavoriteCatalogEntries(R)
    return getOrBuildLookupCache(R, "favoriteCatalogEntries", function()
        local entries = {}

        for _, entry in ipairs(BUILT_IN_FAVORITES) do
            entries[#entries + 1] = {
                Label = trim(entry.Label),
                Action = normalizeAction(entry.Action),
            }
        end

        if trim(R) == "" then
            return entries
        end

        local path = EditorItemService.GetPaths(R).FavoritesCatalog
        local content = readUtf8TextFile(path)
        if not content then
            return entries
        end

        for line in content:gmatch("[^\r\n]+") do
            if not line:match("^%s*#") then
                local label, action = line:match("^([^\t]+)\t(.*)$")
                label = trim(label)
                action = normalizeAction(action)
                if label ~= "" and action ~= "" then
                    entries[#entries + 1] = {
                        Label = label,
                        Action = action,
                    }
                end
            end
        end

        return entries
    end)
end

local function lookupFavoriteCatalogLabel(R, action)
    local normalizedAction = normalizeAction(action)
    if normalizedAction == "" then
        return nil
    end

    local entries = readFavoriteCatalogEntries(R)
    for index = #entries, 1, -1 do
        local entry = entries[index]
        if normalizeAction(entry.Action) == normalizedAction then
            return trim(entry.Label)
        end
    end

    return nil
end

local function describeAppsFolderAction(action, R)
    local directLabel = readProgramActionLabels(R)[trim(action)]
    if directLabel and directLabel ~= "" then
        return directLabel
    end

    local appId = extractAppsFolderAppId(action)
    if not appId then
        return nil
    end

    local cachedLabel = lookupProgramPickerLabel(R, appId)
    if cachedLabel and cachedLabel ~= "" then
        return cachedLabel
    end

    local packageAndApp = splitSegments(appId, "[^!]+")
    local packageFamily = packageAndApp[1] or ""
    local packageName = trim(packageFamily:match("^(.-)_[^_]+$") or packageFamily)
    local packageSegments = splitSegments(packageName, "[^%.]+")
    local appToken = trim(packageAndApp[2] or "")
    local pathLeaf = trim(appId:match("([^/\\]+)$") or "")
    local pathStem = trim(pathLeaf:gsub("%.[^%.]+$", ""))
    local pathSegments = splitSegments(appId, "[^/\\]+")
    local parentSegment = ""
    if #pathSegments > 1 then
        parentSegment = trim(pathSegments[#pathSegments - 1])
        if parentSegment:match("^%b{}$") then
            parentSegment = ""
        end
    end

    local candidate = ""
    if appToken ~= "" and appToken:lower() ~= "app" then
        candidate = humanizeAppToken(appToken)
    end

    if candidate == "" and pathStem ~= "" then
        candidate = humanizeAppToken(pathStem)
    end

    if candidate == "" and parentSegment ~= "" and parentSegment:lower() ~= pathStem:lower() then
        candidate = humanizeAppToken(parentSegment)
    end

    if candidate == "" and #packageSegments > 0 then
        candidate = humanizeAppToken(packageSegments[#packageSegments])
    end

    if candidate == "" then
        candidate = humanizeAppToken(packageName)
    end

    if candidate ~= "" then
        return candidate
    end

    return appId
end

local function normalizeImageAsset(imageAsset)
    local asset = trim(imageAsset):gsub("/", "\\")
    if asset == "" then
        return ""
    end

    if asset:find("\\", 1, true)
        or asset:find("#", 1, true)
        or asset:find("[", 1, true)
        or asset:find("]", 1, true)
        or asset:find('"', 1, true)
        or asset:find(";", 1, true)
        or asset:find("|", 1, true)
        or asset:find(":", 1, true)
        or asset:find("<", 1, true)
        or asset:find(">", 1, true)
        or asset:find("?", 1, true)
        or asset:find("*", 1, true)
        or asset:find("%c") then
        return nil
    end

    local extension = getImageExtension(asset)
    if extension == "" then
        asset = asset .. ".png"
        extension = "png"
    end

    if not SUPPORTED_IMAGE_EXTENSIONS[extension] then
        return nil
    end

    return asset
end

local function isReservedRuntimeImageAsset(imageAsset)
    local asset = normalizeImageAsset(imageAsset)
    return asset ~= nil and asset:lower() == "more.png"
end

function EditorItemService.NormalizeImageAsset(imageAsset)
    return normalizeImageAsset(imageAsset)
end

function EditorItemService.IsReservedRuntimeImageAsset(imageAsset)
    return isReservedRuntimeImageAsset(imageAsset)
end

function EditorItemService.GetImageAdjustmentKey(imageAsset)
    local asset = normalizeImageAsset(imageAsset) or trim(imageAsset)
    return stripImageExtension(asset)
end

function EditorItemService.GetImagePath(R, imageAsset)
    imageAsset = normalizeImageAsset(imageAsset)
    if not imageAsset or imageAsset == "" then
        return ""
    end

    if isReservedRuntimeImageAsset(imageAsset) then
        return EditorItemService.GetPaths(R).RuntimeImageDirectory .. imageAsset
    end

    return EditorItemService.GetPaths(R).ItemImageDirectory .. imageAsset
end

local function buildImageCatalogState()
    local state = {
        assets = {},
        hasCorruptEntries = false,
    }

    for _, variableName in ipairs({ "ItemImageAssets", "ItemImageKeys" }) do
        local rawValue = trim(getVariable(variableName, ""))
        for entry in rawValue:gmatch("[^|]+") do
            local normalizedAsset = normalizeImageAsset(entry)
            if normalizedAsset then
                state.assets[normalizedAsset:lower()] = true
            elseif trim(entry) ~= "" then
                state.hasCorruptEntries = true
            end
        end
    end

    return state
end

function EditorItemService.HasReliableImageCatalog(R)
    return not buildImageCatalogState().hasCorruptEntries
end

function EditorItemService.ImageKeyExists(R, imageAsset)
    imageAsset = normalizeImageAsset(imageAsset)
    if not imageAsset or imageAsset == "" then
        return false
    end

    if isReservedRuntimeImageAsset(imageAsset) then
        return false
    end

    local requestedAsset = imageAsset:lower()
    local catalogState = buildImageCatalogState()
    return catalogState.assets[requestedAsset] == true
end

function EditorItemService.ExtractImageKeyFromPath(R, path)
    local normalizedPath = trim(path):gsub("/", "\\")
    if normalizedPath == "" then
        return nil
    end

    local itemImageDirectory = EditorItemService.GetPaths(R).ItemImageDirectory
    local lowerPath = normalizedPath:lower()
    local lowerDirectory = itemImageDirectory:lower()

    if lowerPath:sub(1, #lowerDirectory) ~= lowerDirectory then
        return nil
    end

    local leaf = normalizedPath:sub(#itemImageDirectory + 1)
    if leaf == "" or leaf:find("\\") then
        return nil
    end

    local imageAsset = normalizeImageAsset(leaf)
    if not imageAsset then
        return nil
    end

    if isReservedRuntimeImageAsset(imageAsset) then
        return nil
    end

    return imageAsset
end

function EditorItemService.IsAppsFolderAction(action)
    return extractAppsFolderAppId(action) ~= nil
end

function EditorItemService.LookupProgramPickerLabel(R, actionOrAppId)
    return lookupProgramPickerLabel(R, actionOrAppId)
end

function EditorItemService.ClearProgramPickerCache(R)
    local path = EditorItemService.GetPaths(R).ProgramPickerCache
    if not tostring(path or ""):find("[\128-\255]") then
        pcall(os.remove, path)
    end
    clearLookupCache(R, "programPickerLabels")
end

function EditorItemService.ClearProgramActionLabelCache(R)
    clearLookupCache(R, "programActionLabels")
end

function EditorItemService.DescribeAction(action, R)
    local normalized = trim(action)
    if normalized == "" then
        return " "
    end

    local favoriteLabel = lookupFavoriteCatalogLabel(R, normalized)
    if favoriteLabel and favoriteLabel ~= "" then
        return favoriteLabel
    end

    local directLabel = readProgramActionLabels(R)[normalized]
    if directLabel and directLabel ~= "" then
        return directLabel
    end

    local appLabel = describeAppsFolderAction(normalized, R)
    if appLabel then
        return appLabel
    end

    local special = SPECIAL_ACTION_LABELS[normalized:lower()]
    if special then
        return special
    end

    local withoutTail = normalized:gsub("[/\\]+$", "")
    local name = withoutTail:match("([^/\\]+)$")
    if name and name ~= "" then
        return name
    end

    return normalized
end

function EditorItemService.ReadDraftSections(R)
    return readSections(R, EditorItemService.GetPaths(R).Draft)
end

function EditorItemService.ReadImageAdjustmentSections(R)
    return readSections(R, R .. "Customs\\Data\\ImageAdjustments.inc")
end

function EditorItemService.ReadPersistedSections(R, source)
    local path = EditorItemService.GetSourceDataPath(R, source)
    if not path then
        return {}
    end
    return readSections(R, path)
end

function EditorItemService.ReadDraftMetaOnly(R)
    return buildDraftMeta(readDraftMetaSections(EditorItemService.GetPaths(R).Draft))
end

function EditorItemService.GetCurrentSessionClockMs()
    return os.time() * 1000
end

function EditorItemService.GetDraftSessionHeartbeatIntervalMs()
    return DRAFT_SESSION_HEARTBEAT_INTERVAL_MS
end

function EditorItemService.GetDraftSessionTimeoutMs()
    return DRAFT_SESSION_TIMEOUT_MS
end

function EditorItemService.IsDraftSessionStale(R, draftMeta)
    local meta = draftMeta or EditorItemService.ReadDraftMetaOnly(R)
    if not meta.EditorOpen then
        return false
    end

    local heartbeatClockMs = toNumber(meta.HeartbeatClockMs, 0)
    if heartbeatClockMs <= 0 then
        return true
    end

    local now = EditorItemService.GetCurrentSessionClockMs()
    if now < heartbeatClockMs then
        return true
    end

    return (now - heartbeatClockMs) > DRAFT_SESSION_TIMEOUT_MS
end

function EditorItemService.IsDraftOpen(R)
    local meta = EditorItemService.ReadDraftMetaOnly(R)
    return meta.EditorOpen and not EditorItemService.IsDraftSessionStale(R, meta)
end

function EditorItemService.IsDraftOpenFast(R)
    return EditorItemService.IsDraftOpen(R)
end

function EditorItemService.ReadDraftMeta(R)
    return EditorItemService.ReadDraftMetaOnly(R)
end

function EditorItemService.GetSectionFromCollection(source, x, y, sections)
    local sectionName = EditorItemService.GetSectionName(source, x, y)
    if not sectionName then
        return nil
    end
    return (sections or {})[sectionName]
end

function EditorItemService.MakeRecord(source, x, y, section, variablePrefix)
    source = normalizeSource(source)
    x = toNumber(x, nil)
    y = toNumber(y, nil)
    if not source or not x or not y then
        return nil
    end

    local sectionName = EditorItemService.GetSectionName(source, x, y)
    if EditorItemService.IsReservedHotbarSlot(source, x, y) then
        local record = cloneRecord(RESERVED_SLOT10)
        local rawLabel = trim(section and section.Label or "")
        local label = trim(resolveVariableReference(section and section.Label or ""))

        if rawLabel == "" or isReservedInventoryLabelValue(rawLabel) or isReservedInventoryLabelValue(label) then
            record.ItemName = reservedInventoryLabel()
        elseif label ~= "" then
            record.ItemName = label
        end
        return record
    end

    return {
        Source = source,
        Section = sectionName,
        x = x,
        y = y,
        ImageKey = normalizeImageAsset(section and section.Image or "") or trim(section and section.Image or ""),
        ItemName = trim(resolveVariableReference(section and section.Label or "")),
        ExecPath = normalizeAction(section and section.Action or ""),
        Qty = toNumber(section and section.Qty or 0, 0),
        Populated = not EditorItemService.IsEmptyItemSection(section),
    }
end

function EditorItemService.GetPersistedSlotRecord(R, source, x, y)
    local sections = EditorItemService.ReadPersistedSections(R, source)
    local section = EditorItemService.GetSectionFromCollection(source, x, y, sections)
    local prefix = normalizeSource(source) == "hotbar" and "HotbarItem" or "InventoryItem"
    return EditorItemService.MakeRecord(source, x, y, section, prefix) or makeEmptyRecord(source, x, y)
end

function EditorItemService.GetDraftSlotRecord(R, source, x, y)
    local section = readDraftSlotSection(R, source, x, y)
    return EditorItemService.MakeRecord(source, x, y, section, "EditorDraftItem") or makeEmptyRecord(source, x, y)
end

function EditorItemService.GetSlotRecord(R, source, x, y)
    if EditorItemService.IsDraftOpen(R) then
        return EditorItemService.GetDraftSlotRecord(R, source, x, y)
    end

    return EditorItemService.GetPersistedSlotRecord(R, source, x, y)
end

function EditorItemService.BuildSourceRecords(R, source, useDraft)
    local records = {}
    local sections = useDraft and EditorItemService.ReadDraftSections(R) or EditorItemService.ReadPersistedSections(R, source)
    source = normalizeSource(source)
    if not source then
        return records
    end

    local bounds = source == "hotbar" and { xMax = 10, yMax = 1 } or { xMax = 9, yMax = 4 }
    for y = 1, bounds.yMax do
        for x = 1, bounds.xMax do
            local prefix
            if useDraft then
                prefix = "EditorDraftItem"
            else
                prefix = source == "hotbar" and "HotbarItem" or "InventoryItem"
            end
            local record = EditorItemService.MakeRecord(source, x, y, EditorItemService.GetSectionFromCollection(source, x, y, sections), prefix)
            if record then
                records[#records + 1] = record
            end
        end
    end

    return records
end

function EditorItemService.BuildInfoList(records)
    local infos = {}
    for _, record in ipairs(records or {}) do
        if record.Populated then
            infos[#infos + 1] = {
                Image = record.ImageKey,
                ItemName = record.ItemName,
                ExecPath = record.ExecPath,
                x = record.x,
                y = record.y,
                qty = record.Qty,
            }
        end
    end

    table.sort(infos, function(a, b)
        if a.y == b.y then
            return a.x < b.x
        end
        return a.y < b.y
    end)

    return infos
end

return EditorItemService
