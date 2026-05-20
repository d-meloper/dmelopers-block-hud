local currentPath = SKIN:GetVariable('CURRENTPATH') or ''
local runtimeRoot = currentPath .. 'Runtime\\'
local sharedLuaRoot = (SKIN:GetVariable('@') or '') .. 'Defaults\\Runtime\\luas\\'

local function loadRuntimeModule(fileName)
    return dofile(runtimeRoot .. fileName)
end

local function loadSharedLuaModule(fileName)
    return dofile(sharedLuaRoot .. fileName)
end

local app = {}
app.schema = loadRuntimeModule('SettingsSchema.lua')
app.state = loadRuntimeModule('SettingsState.lua')(#app.schema.tabs)
app.methods = {}
app.localization = loadSharedLuaModule('Localization.lua')

function app.trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

function app.shallowCopy(source)
    local target = {}
    for key, value in pairs(source or {}) do
        target[key] = value
    end
    return target
end

function app.snapshotSignature(snapshot)
    local fragments = {}
    for key, value in pairs(snapshot or {}) do
        fragments[#fragments + 1] = key .. '=' .. tostring(value)
    end
    table.sort(fragments)
    return table.concat(fragments, '|')
end

function app.setVariable(name, value)
    SKIN:Bang('!SetVariable', name, tostring(value or ''))
end

function app.logNotice(message)
    local text = tostring(message or '')
    SKIN:Bang('!Log', text, 'Notice')
    if app.methods and app.methods.appendSettingsRuntimeLog then
        app.methods.appendSettingsRuntimeLog(text)
    end
end

function app.methods.localize(key, fallback)
    return app.localization.Get(SKIN, key, fallback)
end

function app.methods.localizationVariableRef(key)
    local resolvedKey = app.trim(key)
    if resolvedKey == '' then
        return ''
    end
    if not resolvedKey:match('^Loc_') then
        resolvedKey = 'Loc_' .. resolvedKey
    end
    if app.trim(SKIN:GetVariable(resolvedKey, '')) == '' then
        return ''
    end
    return '#' .. resolvedKey .. '#'
end

function app.methods.localizeFormat(key, args, fallback)
    return app.localization.Format(SKIN, key, args, fallback)
end

function app.methods.getField(fieldKey)
    return app.schema.fields[fieldKey]
end

function app.methods.activeTab()
    return app.schema.tabs[app.state.currentTabIndex]
end

function app.methods.activePageIndex()
    return app.state.currentPageByTab[app.state.currentTabIndex] or 1
end

function app.methods.getTabPageCount(tab)
    local maxPage = 1
    for _, fieldKey in ipairs(tab.fields) do
        local field = app.methods.getField(fieldKey)
        local pageId = field and field.pageId or 1
        if pageId > maxPage then
            maxPage = pageId
        end
    end
    return maxPage
end

function app.methods.hasDropdown(field)
    return field and field.controlType == 'text' and app.trim(field.dropdownId or '') ~= ''
end

loadRuntimeModule('SettingsTheme.lua')(app)
loadRuntimeModule('SettingsPersistence.lua')(app)
loadRuntimeModule('SettingsNotice.lua')(app)
loadRuntimeModule('SettingsDropdown.lua')(app)
loadRuntimeModule('SettingsCache.lua')(app)
loadRuntimeModule('SettingsRender.lua')(app)
loadRuntimeModule('SettingsActions.lua')(app)

PrepareTextField = app.methods.PrepareTextField
RestorePersistentCache = app.methods.RestorePersistentCache
ScheduleDropdownDataLoad = app.methods.ScheduleDropdownDataLoad
CancelPendingLoad = app.methods.CancelPendingLoad
RunPendingLoad = app.methods.RunPendingLoad
HandleHelperComplete = app.methods.HandleHelperComplete
HandleDetachedHelperComplete = app.methods.HandleDetachedHelperComplete
RunPendingVersionManagerLaunch = app.methods.RunPendingVersionManagerLaunch
RunPendingRefresh = app.methods.RunPendingRefresh
RunPendingLanguageSwitch = app.methods.RunPendingLanguageSwitch
ActivateVisibleRowInput = app.methods.ActivateVisibleRowInput
StepVisibleRowDown = app.methods.StepVisibleRowDown
StepVisibleRowUp = app.methods.StepVisibleRowUp
ToggleVisibleRowDropdown = app.methods.ToggleVisibleRowDropdown
SelectDropdownOption = app.methods.SelectDropdownOption
DeleteDropdownOption = app.methods.DeleteDropdownOption
PrevDropdownOptionPage = app.methods.PrevDropdownOptionPage
NextDropdownOptionPage = app.methods.NextDropdownOptionPage
CommitPendingInput = app.methods.CommitPendingInput
ToggleField = app.methods.ToggleField
AdjustField = app.methods.AdjustField
StepFieldDown = app.methods.StepFieldDown
StepFieldUp = app.methods.StepFieldUp
ExecuteVisibleRowAction = app.methods.ExecuteVisibleRowAction
ExecuteVisibleRowSecondaryAction = app.methods.ExecuteVisibleRowSecondaryAction
ExecuteFieldAction = app.methods.ExecuteFieldAction
PrevTab = app.methods.PrevTab
NextTab = app.methods.NextTab
PrevPage = app.methods.PrevPage
NextPage = app.methods.NextPage
UndoChange = app.methods.UndoChange
RedoChange = app.methods.RedoChange
ResetSession = app.methods.ResetSession
ResetToDefaults = app.methods.ResetToDefaults
CancelPendingConfirmation = app.methods.CancelPendingConfirmation
CancelResetToDefaults = app.methods.CancelPendingConfirmation
CloseSettings = app.methods.CloseSettings
HandleClose = app.methods.HandleClose
Initialize = app.methods.Initialize

return app
