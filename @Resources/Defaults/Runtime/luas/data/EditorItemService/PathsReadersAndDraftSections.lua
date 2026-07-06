-- Split from @Resources\Defaults\Runtime\luas\data\EditorItemService.lua lines 1-768.
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
    ConfirmBeforeRun = "0",
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

local function normalizeConfirmBeforeRun(value)
    return trim(value) == "1" and "1" or "0"
end
local VARIABLE_MISSING = "__DMCS_VARIABLE_MISSING__"
local ITEM_KEYS = { "Image", "Label", "Action", "Qty", "ConfirmBeforeRun" }
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
        ConfirmBeforeRun = normalizeConfirmBeforeRun(record.ConfirmBeforeRun),
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
        ConfirmBeforeRun = "0",
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
