return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    local function resolveRootConfigFromCurrentConfig()
        local currentConfig = trim(SKIN:GetVariable('CURRENTCONFIG', ''))
        local rootConfig = trim(SKIN:GetVariable('ROOTCONFIG', '')):gsub('/', '\\')
        local normalizedCurrentConfig = currentConfig:gsub('/', '\\')
        if rootConfig ~= ''
            and (normalizedCurrentConfig:lower() == rootConfig:lower()
                or normalizedCurrentConfig:lower():sub(1, #rootConfig + 1) == (rootConfig:lower() .. '\\')) then
            return rootConfig
        end
        local parentConfig = currentConfig:match('^(.*)[\\/][^\\/]+$')
        if parentConfig and parentConfig ~= '' then
            local parentLeaf = parentConfig:match('[^\\/]+$') or ''
            if parentLeaf == 'HUD' or parentLeaf == 'Utilities' or parentLeaf == 'ExtraContent' then
                local rootParentConfig = parentConfig:match('^(.*)[\\/][^\\/]+$')
                if rootParentConfig and rootParentConfig ~= '' then
                    return rootParentConfig
                end
            end
            return parentConfig
        end
        return rootConfig
    end

    local function resolveSkinRootFromCurrentPath()
        local settingsPath = trim(SKIN:GetVariable('CURRENTPATH', ''))
        settingsPath = settingsPath:gsub('[\\/]+$', '')
        local parentPath = settingsPath:match('^(.*)[\\/][^\\/]+$') or settingsPath
        local parentLeaf = parentPath:match('[^\\/]+$') or ''
        if parentLeaf == 'HUD' then
            return parentPath:match('^(.*)[\\/][^\\/]+$') or parentPath
        end
        return parentPath
    end


    function methods.ensurePaths()

        if not state.resourcesRoot then

            state.resourcesRoot = SKIN:GetVariable('@')

            state.settingsRoot = state.resourcesRoot .. 'Customs\\Settings\\'

            state.rootConfig = resolveRootConfigFromCurrentConfig()

        end

    end



    function methods.localizationLanguagesRoot()
        methods.ensurePaths()
        return state.resourcesRoot .. 'Localization\\Languages\\'
    end

    function methods.activeLocalizationPath()
        methods.ensurePaths()
        return state.resourcesRoot .. 'Customs\\Localization\\Active.inc'
    end

    function methods.hotbarItemsPath()
        methods.ensurePaths()
        return state.resourcesRoot .. 'Customs\\Data\\HotbarItems.inc'
    end

    function methods.inventoryItemsPath()
        methods.ensurePaths()
        return state.resourcesRoot .. 'Customs\\Data\\InventoryItems.inc'
    end

    function methods.editorDraftPath()
        methods.ensurePaths()
        return state.resourcesRoot .. 'Customs\\Data\\EditorDraft.inc'
    end

    function methods.normalizeLanguageCode(raw, fallback)
        return app.languageRegistry.NormalizeLanguageCode(SKIN, raw, fallback)
    end

    function methods.reservedInventoryLabelForLanguage(languageCode)
        return app.languageRegistry.GetInventoryLabel(SKIN, languageCode)
    end

    local quoteCommandArgument = nil

    local function syncReservedInventoryLabel(path, variableName, actionVariableName, reservedLabel)
        if trim(SKIN:GetVariable(actionVariableName, '')) ~= '_OPEN_INVENTORY_' then
            return false
        end
        if not reservedLabel or reservedLabel == '' then
            return false
        end

        local currentValue = trim(SKIN:GetVariable(variableName, ''))
        if currentValue == reservedLabel then
            return false
        end

        methods.writeIniVariable(path, variableName, reservedLabel)
        return true
    end

    function methods.defaultItemLabelsScriptPath()
        return '..\\..\\Utilities\\tools\\Update-DefaultItemLabels.ps1'
    end

    function methods.startDefaultItemLabelLocalization(languageCode, options)
        methods.ensurePaths()
        options = options or {}
        local resolvedLanguage = methods.normalizeLanguageCode(languageCode, methods.normalizeLanguageCode(nil, nil))
        local measureName = 'MeasureSettingsDefaultItemLabelsRun'
        if not SKIN:GetMeasure(measureName) then
            methods.appendSettingsRuntimeLog('Default item label localization run measure is missing.')
            return false
        end
        local skinRoot = resolveSkinRootFromCurrentPath()
        local args = '-ExecutionPolicy Bypass -File '
            .. quoteCommandArgument(methods.defaultItemLabelsScriptPath())
            .. ' -SkinRoot '
            .. quoteCommandArgument(skinRoot)
            .. ' -LanguageCode '
            .. quoteCommandArgument(resolvedLanguage)

        state.pendingDefaultItemLocalizationRunning = true
        state.pendingDefaultItemLocalizationLanguage = resolvedLanguage
        state.pendingDefaultItemLocalizationRefreshApp = options.refreshAppOnComplete == true
        state.pendingDefaultItemLocalizationTargetSet = options.targetSet
        state.pendingDefaultItemLocalizationRefreshOptions = options.refreshOptions

        setVariable('SettingsDefaultItemLabelsArgs', args)
        SKIN:Bang('!UpdateMeasure', measureName)
        SKIN:Bang('!CommandMeasure', measureName, 'Run')
        return true
    end

    function methods.syncItemLabelsForLanguage(languageCode, options)
        options = options or {}
        local resolved = methods.normalizeLanguageCode(languageCode, methods.normalizeLanguageCode(nil, nil))
        local reservedLabel = methods.reservedInventoryLabelForLanguage(resolved)
        local changed = false

        local hotbarPath = methods.hotbarItemsPath()
        changed = syncReservedInventoryLabel(
            hotbarPath,
            'HotbarItem_Slot10_Label',
            'HotbarItem_Slot10_Action',
            reservedLabel
        ) or changed

        local editorDraftPath = methods.editorDraftPath()
        changed = syncReservedInventoryLabel(
            editorDraftPath,
            'EditorDraftItem_Slot10_Label',
            'EditorDraftItem_Slot10_Action',
            reservedLabel
        ) or changed

        if methods.startDefaultItemLabelLocalization(resolved, options) then
            return true
        end

        return changed
    end

    function methods.HandleDefaultItemLabelsComplete()
        local measure = SKIN:GetMeasure('MeasureSettingsDefaultItemLabelsRun')
        local raw = ''
        if measure then
            raw = tostring(measure:GetStringValue() or '')
        end
        local values = methods.parseCommandCaptureVariables and methods.parseCommandCaptureVariables(raw) or {}
        local status = string.upper(trim(values.DMEL_STATUS or ''))
        if status ~= 'OK' then
            local message = trim(values.DMEL_MESSAGE or '')
            if message == '' then
                message = 'Default item label localization helper did not report success.'
            end
            methods.appendSettingsRuntimeLog(message)
        end

        local shouldRefreshApp = state.pendingDefaultItemLocalizationRefreshApp == true
        local targetSet = state.pendingDefaultItemLocalizationTargetSet
        local refreshOptions = state.pendingDefaultItemLocalizationRefreshOptions
        state.pendingDefaultItemLocalizationRunning = false
        state.pendingDefaultItemLocalizationLanguage = nil
        state.pendingDefaultItemLocalizationRefreshApp = nil
        state.pendingDefaultItemLocalizationTargetSet = nil
        state.pendingDefaultItemLocalizationRefreshOptions = nil

        if shouldRefreshApp then
            SKIN:Bang('!RefreshApp')
            return true
        end

        if targetSet then
            methods.refreshTargets(targetSet, refreshOptions)
            return true
        end

        return status == 'OK'
    end

    function methods.languageSwitchLoadingText(languageCode)
        local fallback = methods.normalizeLanguageCode(languageCode, methods.normalizeLanguageCode(nil, nil)) == 'ko-KR'
            and methods.localize('Settings_Loading', 'Loading...\nPlease wait.')
            or 'Changing language...\nPlease wait.'
        return methods.localize('Settings_Loading_LanguageSwitch', fallback)
    end

    function methods.syncActiveLocalization(languageCode)
        local resolved = methods.normalizeLanguageCode(languageCode, methods.normalizeLanguageCode(nil, nil))
        if methods.syncHelperLocalizationCache then
            methods.syncHelperLocalizationCache(resolved)
        end
        return true
    end

    quoteCommandArgument = function(value)
        local resolved = tostring(value or '')
        resolved = resolved:gsub('"', '\\"')
        return '"' .. resolved .. '"'
    end

    function methods.helperLocalizationCacheScriptPath()
        return '..\\..\\Utilities\\tools\\UpdateHelperLocalizationCache.ps1'
    end

    function methods.syncHelperLocalizationCache(languageCode)
        methods.ensurePaths()
        local resolvedLanguage = methods.normalizeLanguageCode(languageCode, methods.normalizeLanguageCode(nil, nil))
        local measureName = 'MeasureSettingsHelperLocalizationCacheRun'
        if not SKIN:GetMeasure(measureName) then
            methods.appendSettingsRuntimeLog('Helper localization cache run measure is missing.')
            return false
        end
        local skinRoot = resolveSkinRootFromCurrentPath()
        local args = '-ExecutionPolicy Bypass -File '
            .. quoteCommandArgument(methods.helperLocalizationCacheScriptPath())
            .. ' -SkinRoot '
            .. quoteCommandArgument(skinRoot)
            .. ' -LanguageCode '
            .. quoteCommandArgument(resolvedLanguage)
        setVariable('SettingsHelperLocalizationCacheArgs', args)
        SKIN:Bang('!UpdateMeasure', measureName)
        SKIN:Bang('!CommandMeasure', measureName, 'Run')
        return true
    end
    function methods.responsiveLayoutCore()

        methods.ensurePaths()

        if not state.responsiveLayoutCore then

            state.responsiveLayoutCore = app.loadSharedLuaModule('ResponsiveLayoutCore.lua')

        end

        return state.responsiveLayoutCore

    end



    function methods.statePath()

        return trim(SKIN:GetVariable('CURRENTPATH', '')) .. 'State.inc'

    end



    function methods.cachePath()

        return trim(SKIN:GetVariable('CURRENTPATH', '')) .. 'Cache.inc'

    end



    function methods.defaultSnapshotPath()

        return trim(SKIN:GetVariable('CURRENTPATH', '')) .. 'DefaultSnapshot.inc'

    end



    function methods.fetchMinecraftSkinScriptPath()

        return '.\\FetchMinecraftSkin.ps1'

    end

    function methods.playerSkinImageDirectoryPath()

        methods.ensurePaths()

        return state.resourcesRoot .. 'Customs\\Images\\Player'

    end

    function methods.minecraftSkinHistoryPath()

        methods.ensurePaths()

        return state.resourcesRoot .. 'Customs\\Data\\MinecraftSkinHistory.txt'

    end

    function methods.logsRootPath()

        methods.ensurePaths()

        return trim(SKIN:GetVariable('ROOTCONFIGPATH', '')) .. 'Logs'

    end

    function methods.ensureCachedDirectory(path)

        local resolved = trim(path or '')

        if resolved == '' then

            return ''

        end

        resolved = resolved:gsub('[\\/]+$', '')

        if resolved == '' then

            return ''

        end

        if type(state.cachedDirectories) ~= 'table' then

            state.cachedDirectories = {}

        end

        if not state.cachedDirectories[resolved] then

            os.execute('if not exist "' .. resolved .. '" mkdir "' .. resolved .. '" >nul 2>nul')

            state.cachedDirectories[resolved] = true

        end

        return resolved

    end

    function methods.skinWideLogPath()

        return methods.logsRootPath() .. "\\DMeloper's Block HUD Log.log"

    end

    function methods.settingsRuntimeLogPath()

        return methods.skinWideLogPath()

    end
    function methods.appendSettingsRuntimeLog(message)

        local path = methods.settingsRuntimeLogPath()

        if trim(path) == '' then

            return false

        end

        methods.ensureCachedDirectory(path:match('^(.*)[\\/]') or '')

        local handle = io.open(path, 'ab')

        if not handle then

            return false

        end

        handle:write('<SettingsRuntime>\r\n' .. os.date('%Y-%m-%d %H:%M:%S') .. ' [Settings] ' .. tostring(message or '') .. '\r\n')

        handle:close()

        return true

    end

    function methods.minecraftSkinDebugLogPath()

        return methods.skinWideLogPath()

    end
    function methods.appendMinecraftSkinDebugLog(message)

        local path = methods.minecraftSkinDebugLogPath()

        if trim(path) == '' then

            return false

        end

        methods.ensureCachedDirectory(path:match('^(.*)[\\/]') or '')

        local handle = io.open(path, 'ab')

        if not handle then

            return false

        end

        handle:write('<MinecraftSkin>\r\n' .. os.date('%Y-%m-%d %H:%M:%S') .. ' [Settings] ' .. tostring(message or '') .. '\r\n')

        handle:close()

        return true

    end
end
