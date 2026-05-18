return function(app)

    local state = app.state

    local schema = app.schema

    local methods = app.methods

    local trim = app.trim

    local shallowCopy = app.shallowCopy

    local logNotice = app.logNotice

    local setVariable = app.setVariable

    local MINECRAFT_SKIN_HISTORY_LIMIT = 12


    local function resolveRootConfigFromCurrentConfig()
        local currentConfig = trim(SKIN:GetVariable('CURRENTCONFIG', ''))
        local parentConfig = currentConfig:match('^(.*)[\\/][^\\/]+$')
        if parentConfig and parentConfig ~= '' then
            return parentConfig
        end
        return trim(SKIN:GetVariable('ROOTCONFIG', ''))
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
        local resolved = string.lower(trim(raw))
        if resolved == 'en' or resolved == 'en-us' then
            return 'en-US'
        end
        if resolved == 'ko' or resolved == 'ko-kr' then
            return 'ko-KR'
        end
        local fallbackResolved = string.lower(trim(fallback))
        if fallbackResolved == 'en-us' then
            return 'en-US'
        end
        return 'ko-KR'
    end

    local RESERVED_INVENTORY_LABEL_BY_LANGUAGE = {
        ['ko-KR'] = '인벤토리',
        ['en-US'] = 'Inventory',
    }

    function methods.reservedInventoryLabelForLanguage(languageCode)
        local resolved = methods.normalizeLanguageCode(languageCode, 'ko-KR')
        return RESERVED_INVENTORY_LABEL_BY_LANGUAGE[resolved]
            or RESERVED_INVENTORY_LABEL_BY_LANGUAGE['ko-KR']
    end

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

    function methods.syncItemLabelsForLanguage(languageCode)
        local resolved = methods.normalizeLanguageCode(languageCode, 'ko-KR')
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

        return changed
    end

    function methods.languageSwitchLoadingText(languageCode)
        local fallback = methods.normalizeLanguageCode(languageCode, 'ko-KR') == 'en-US'
            and 'Changing language...\nPlease wait.'
            or methods.localize('Settings_Loading', 'Loading...\nPlease wait.')
        return methods.localize('Settings_Loading_LanguageSwitch', fallback)
    end

    function methods.persistPendingLanguageFanoutRequest(languageCode)
        local resolved = methods.normalizeLanguageCode(languageCode, 'ko-KR')
        methods.writeIniVariable(methods.cachePath(), 'SettingsPendingLanguageFanout', '1')
        methods.writeIniVariable(methods.cachePath(), 'SettingsPendingLanguageCode', resolved)
        return resolved
    end

    function methods.clearPendingLanguageFanoutRequest()
        methods.writeIniVariable(methods.cachePath(), 'SettingsPendingLanguageFanout', '0')
        methods.writeIniVariable(methods.cachePath(), 'SettingsPendingLanguageCode', '')
    end

    function methods.consumePendingLanguageFanoutRequest()
        local fanout = trim(SKIN:GetVariable('SettingsPendingLanguageFanout', '0'))
        local code = trim(SKIN:GetVariable('SettingsPendingLanguageCode', ''))
        if fanout ~= '1' then
            return ''
        end
        local resolved = methods.normalizeLanguageCode(code, 'ko-KR')
        methods.clearPendingLanguageFanoutRequest()
        return resolved
    end

    function methods.syncActiveLocalization(languageCode)
        local resolved = methods.normalizeLanguageCode(languageCode, 'ko-KR')
        if methods.syncHelperLocalizationCache then
            methods.syncHelperLocalizationCache(resolved)
        end
        return true
    end

    local function quoteCommandArgument(value)
        local resolved = tostring(value or '')
        resolved = resolved:gsub('"', '\\"')
        return '"' .. resolved .. '"'
    end

    function methods.helperLocalizationCacheScriptPath()
        methods.ensurePaths()
        local settingsPath = trim(SKIN:GetVariable('CURRENTPATH', ''))
        settingsPath = settingsPath:gsub('[\\/]+$', '')
        local skinRoot = settingsPath:match('^(.*)[\\/][^\\/]+$') or settingsPath
        return skinRoot .. '\\tools\\UpdateHelperLocalizationCache.ps1'
    end

    function methods.syncHelperLocalizationCache(languageCode)
        methods.ensurePaths()
        local resolvedLanguage = methods.normalizeLanguageCode(languageCode, 'ko-KR')
        local measureName = 'MeasureSettingsHelperLocalizationCacheRun'
        if not SKIN:GetMeasure(measureName) then
            methods.appendSettingsRuntimeLog('Helper localization cache run measure is missing.')
            return false
        end
        local settingsPath = trim(SKIN:GetVariable('CURRENTPATH', ''))
        settingsPath = settingsPath:gsub('[\\/]+$', '')
        local skinRoot = settingsPath:match('^(.*)[\\/][^\\/]+$') or settingsPath
        local args = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File '
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

            state.responsiveLayoutCore = dofile(state.resourcesRoot .. 'Defaults\\Runtime\\luas\\ResponsiveLayoutCore.lua')

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



    function methods.startupAutoRunScriptPath()

        return trim(SKIN:GetVariable('CURRENTPATH', '')) .. 'StartupAutoRun.ps1'

    end

    function methods.fetchMinecraftSkinScriptPath()

        return trim(SKIN:GetVariable('CURRENTPATH', '')) .. 'FetchMinecraftSkin.ps1'

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

    function methods.minecraftSkinImagePathForUsername(username)

        local sanitized = methods.sanitizeMinecraftSkinFileComponent(username)

        if sanitized == '' then

            return ''

        end

        return methods.playerSkinImageDirectoryPath() .. '\\MinecraftSkinBody_' .. sanitized .. '.png'

    end

    function methods.isBuiltInMinecraftSkinUsername(username)

        return string.lower(trim(tostring(username or ''))) == 'alex'

    end

    function methods.sameNormalizedPath(left, right)

        local leftValue = trim(tostring(left or '')):gsub('/', '\\'):lower()

        local rightValue = trim(tostring(right or '')):gsub('/', '\\'):lower()

        return leftValue ~= '' and rightValue ~= '' and leftValue == rightValue

    end

    function methods.isMinecraftSkinImagePathVerified(imagePath)

        if trim(tostring(imagePath or '')) == '' then

            return false

        end

        local raw = string.lower(trim(SKIN:GetVariable('MinecraftSkinImagePathVerified', '0')))

        if raw ~= '1' and raw ~= 'true' then

            return false

        end

        local currentImagePath = trim(SKIN:GetVariable('MinecraftSkinImagePath', ''))

        return methods.sameNormalizedPath(currentImagePath, imagePath)

    end

    function methods.resolveStoredMinecraftSkinImagePath(username, imagePath, options)

        local resolvedUsername = trim(tostring(username or ''))

        if resolvedUsername == '' then

            return ''

        end

        local expectedImagePath = methods.minecraftSkinImagePathForUsername(resolvedUsername)

        local candidateImagePath = trim(tostring(imagePath or ''))

        local allowStoredWidePath = options and options.allowStoredWidePath == true

        if candidateImagePath ~= '' and expectedImagePath ~= '' and methods.sameNormalizedPath(candidateImagePath, expectedImagePath) and (methods.isPngFile(candidateImagePath) or (allowStoredWidePath and methods.isStoredWidePngPath(candidateImagePath))) then

            return candidateImagePath

        end

        if expectedImagePath ~= '' and methods.isPngFile(expectedImagePath) then

            return expectedImagePath

        end

        return ''

    end

    function methods.resolveVerifiedLocalMinecraftSkinImagePath(username, imagePath, options)

        local resolvedUsername = trim(tostring(username or ''))

        if resolvedUsername == '' then

            return ''

        end

        local expectedImagePath = methods.minecraftSkinImagePathForUsername(resolvedUsername)

        local candidateImagePath = trim(tostring(imagePath or ''))

        local allowStoredWidePath = options and options.allowStoredWidePath == true

        if candidateImagePath ~= '' and expectedImagePath ~= '' and methods.sameNormalizedPath(candidateImagePath, expectedImagePath) and (methods.isPngFile(candidateImagePath) or (allowStoredWidePath and methods.isStoredWidePngPath(candidateImagePath))) then

            return candidateImagePath

        end

        if expectedImagePath ~= '' and methods.isPngFile(expectedImagePath) then

            return expectedImagePath

        end

        return ''

    end

    function methods.fileExists(path)

        local handle = io.open(path, 'rb')

        if not handle then

            return false

        end

        handle:close()

        return true

    end

    function methods.isPngFile(path)

        local handle = io.open(path, 'rb')

        if not handle then

            return false

        end

        local signature = handle:read(8) or ''

        handle:close()

        local expected = { 137, 80, 78, 71, 13, 10, 26, 10 }

        if #signature ~= #expected then

            return false

        end

        for index, value in ipairs(expected) do

            if signature:byte(index) ~= value then

                return false

            end

        end

        return true

    end

    function methods.isStoredWidePngPath(path)

        local resolved = trim(tostring(path or ''))

        return resolved ~= '' and resolved:find('[\128-\255]') ~= nil and resolved:lower():match('%.png$') ~= nil

    end

    function methods.sanitizeMinecraftSkinFileComponent(value)

        local resolved = trim(tostring(value or ''))

        if resolved == '' then

            return ''

        end

        resolved = resolved:gsub('[<>:""/\\|%?%*]', '_')

        resolved = resolved:gsub('[%c]', '_')

        return trim(resolved)

    end

    function methods.syncMinecraftSkinDraft(value)

        local field = methods.getField('minecraftSkinUsernameDraft')

        if not field then

            return ''

        end

        local resolved = trim(tostring(value or ''))

        methods.setFieldSessionValue(field, resolved)

        return resolved

    end

    function methods.syncMinecraftSkinDraftFromCanonical()

        local field = methods.getField('minecraftSkinUsername')

        if not field then

            return methods.syncMinecraftSkinDraft('')

        end

        local username = trim(methods.readFieldValue(field))

        local storedImagePath = trim(SKIN:GetVariable('MinecraftSkinImagePath', ''))

        local storedImagePathVerified = methods.isMinecraftSkinImagePathVerified(storedImagePath)

        local resolvedImagePath = methods.resolveStoredMinecraftSkinImagePath(username, storedImagePath, { allowStoredWidePath = storedImagePathVerified })

        local resolvedImagePathVerified = resolvedImagePath ~= '' and (storedImagePathVerified or methods.isPngFile(resolvedImagePath))

        if (storedImagePath ~= '' or resolvedImagePath ~= '') and not methods.sameNormalizedPath(storedImagePath, resolvedImagePath) then

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePath', resolvedImagePath)

            setVariable('MinecraftSkinImagePath', resolvedImagePath)

        end

        if trim(SKIN:GetVariable('MinecraftSkinImagePathVerified', '0')) ~= (resolvedImagePathVerified and '1' or '0') then

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePathVerified', resolvedImagePathVerified and '1' or '0')

            setVariable('MinecraftSkinImagePathVerified', resolvedImagePathVerified and '1' or '0')

        end

        return methods.syncMinecraftSkinDraft(username)

    end



    function methods.startupAutoRunCapturePath()

        local systemRoot = trim((os and os.getenv and os.getenv('SystemRoot')) or 'C:\\Windows')

        if systemRoot == '' then

            systemRoot = 'C:\\Windows'

        end

        systemRoot = systemRoot:gsub('[\\\\/]+$', '')

        return systemRoot .. '\\Temp\\dmel_settings_startup_autorun.txt'

    end



    function methods.readPlainTextFile(path)

        local handle = io.open(path, 'rb')

        if not handle then

            return ''

        end

        local data = handle:read('*all') or ''

        handle:close()

        if data:sub(1, 3) == '\239\187\191' then

            data = data:sub(4)

        end

        return data

    end



    function methods.writePlainTextFile(path, data)

        local tempPath = tostring(path or '') .. '.tmp'

        local handle = io.open(tempPath, 'wb')

        if not handle then

            return false

        end

        handle:write(tostring(data or ''))

        handle:close()

        pcall(os.remove, path)

        local renamed = os.rename(tempPath, path)

        if renamed then

            return true

        end

        local fallback = io.open(path, 'wb')

        if not fallback then

            pcall(os.remove, tempPath)

            return false

        end

        fallback:write(tostring(data or ''))

        fallback:close()

        pcall(os.remove, tempPath)

        return true

    end

    function methods.readMinecraftSkinHistoryNames()

        local values = {}

        local seen = {}

        local raw = methods.readPlainTextFile(methods.minecraftSkinHistoryPath())

        for entry in tostring(raw or ''):gmatch('[^\r\n]+') do

            local trimmedEntry = trim(entry)

            local key = string.lower(trimmedEntry)

            if trimmedEntry ~= '' and not seen[key] then

                values[#values + 1] = trimmedEntry

                seen[key] = true

                if #values >= MINECRAFT_SKIN_HISTORY_LIMIT then

                    break

                end

            end

        end

        return values

    end

    function methods.writeMinecraftSkinHistoryNames(names)

        local values = {}

        local seen = {}

        for _, entry in ipairs(names or {}) do

            local trimmedEntry = trim(entry)

            local key = string.lower(trimmedEntry)

            if trimmedEntry ~= '' and not seen[key] then

                values[#values + 1] = trimmedEntry

                seen[key] = true

                if #values >= MINECRAFT_SKIN_HISTORY_LIMIT then

                    break

                end

            end

        end

        local data = ''

        if #values > 0 then

            data = table.concat(values, '\n') .. '\n'

        end

        return methods.writePlainTextFile(methods.minecraftSkinHistoryPath(), data)

    end

    function methods.rememberMinecraftSkinHistory(username)

        local resolved = trim(tostring(username or ''))

        if resolved == '' or methods.isBuiltInMinecraftSkinUsername(resolved) then

            return {}

        end

        local values = { resolved }

        local seen = { [string.lower(resolved)] = true }

        for _, entry in ipairs(methods.readMinecraftSkinHistoryNames()) do

            if #values >= MINECRAFT_SKIN_HISTORY_LIMIT then

                break

            end

            local trimmedEntry = trim(entry)

            local key = string.lower(trimmedEntry)

            if trimmedEntry ~= '' and not seen[key] then

                values[#values + 1] = trimmedEntry

                seen[key] = true

            end

        end

        methods.writeMinecraftSkinHistoryNames(values)

        return values

    end

    function methods.removeMinecraftSkinHistoryName(username)

        local targetKey = string.lower(trim(username))

        if targetKey == '' then

            return false

        end

        local values = {}

        local changed = false

        for _, entry in ipairs(methods.readMinecraftSkinHistoryNames()) do

            local trimmedEntry = trim(entry)

            if string.lower(trimmedEntry) == targetKey then

                changed = true

            else

                values[#values + 1] = trimmedEntry

            end

        end

        if changed then

            methods.writeMinecraftSkinHistoryNames(values)

        end

        return changed

    end
    function methods.resolveLocalMinecraftSkinResult(username)

        local resolved = trim(tostring(username or ''))

        if resolved == '' then

            methods.appendMinecraftSkinDebugLog('resolveLocalMinecraftSkinResult skipped because username is blank')

            return nil

        end

        local canonicalField = methods.getField('minecraftSkinUsername')

        local canonicalUsername = canonicalField and trim(methods.readFieldValue(canonicalField)) or ''

        local canonicalStoredImagePath = SKIN:GetVariable('MinecraftSkinImagePath', '')

        local canonicalImagePath = methods.resolveVerifiedLocalMinecraftSkinImagePath(canonicalUsername, canonicalStoredImagePath, { allowStoredWidePath = methods.isMinecraftSkinImagePathVerified(canonicalStoredImagePath) })

        local requestedKey = string.lower(resolved)

        local canonicalKey = string.lower(canonicalUsername)

        local hasCanonicalPng = canonicalImagePath ~= ''

        methods.appendMinecraftSkinDebugLog('resolveLocalMinecraftSkinResult username=' .. resolved .. ' canonicalUsername=' .. canonicalUsername .. ' canonicalImagePath=' .. tostring(canonicalImagePath) .. ' hasCanonicalPng=' .. tostring(hasCanonicalPng))

        if canonicalKey ~= '' and canonicalKey == requestedKey and hasCanonicalPng then

            return {

                status = 'OK',

                username = canonicalUsername,

                imagePath = canonicalImagePath,

                message = '',

            }

        end

        local imagePath = methods.minecraftSkinImagePathForUsername(resolved)

        local hasPng = imagePath ~= '' and methods.isPngFile(imagePath)

        methods.appendMinecraftSkinDebugLog('resolveLocalMinecraftSkinResult username=' .. resolved .. ' path=' .. tostring(imagePath) .. ' hasPng=' .. tostring(hasPng))

        if hasPng then

            return {

                status = 'OK',

                username = resolved,

                imagePath = imagePath,

                message = '',

            }

        end

        return nil

    end
    function methods.escapeCommandArgument(value)

        local resolved = tostring(value or '')

        return '"' .. resolved:gsub('"', '""') .. '"'

    end



    function methods.parseStartupAutoRunLiteral(raw, fallback)

        local literal = tostring(fallback or '0')

        for line in tostring(raw or ''):gmatch('[^\r\n]+') do

            local trimmedLine = trim(line)

            if trimmedLine == '0' or trimmedLine == '1' then

                literal = trimmedLine

            end

        end

        return literal

    end



    function methods.startupAutoRunCacheInitialized()

        return methods.readPersistentCacheVariable('SettingsPersistentCacheStartupAutoRunInitialized', '0') == '1'

    end



    function methods.startupAutoRunCachedValue()

        return methods.normalizeToggleValue(methods.readPersistentCacheVariable('SettingsPersistentCacheStartupAutoRunValue', '0'))

    end



    function methods.persistStartupAutoRunCache(literal)

        methods.writePersistentCacheVariable('SettingsPersistentCacheFormatVersion', state.cacheFormatVersion)

        methods.writePersistentCacheVariable('SettingsPersistentCacheStartupAutoRunInitialized', '1')

        methods.writePersistentCacheVariable('SettingsPersistentCacheStartupAutoRunValue', methods.normalizeToggleValue(literal))

    end



    function methods.persistStartupAutoRunSetting(literal, options)

        options = options or {}

        local field = methods.getField('startupAutoRun')

        if not field then

            return

        end

        local normalized = methods.normalizeToggleValue(literal)

        local currentLiteral = options.currentLiteral ~= nil and methods.normalizeToggleValue(options.currentLiteral) or methods.normalizeToggleValue(methods.readFieldValue(field))

        if options.force ~= true and currentLiteral == normalized then

            return

        end

        methods.writeIniVariable(methods.settingsFilePath(field.settingsFile), field.variableName, normalized)

    end



    function methods.resolveStartupAutoRunState(desiredLiteral)

        local field = methods.getField('startupAutoRun')

        local fallback = field and methods.normalizeToggleValue(methods.readFieldValue(field)) or '0'

        if desiredLiteral ~= nil then

            return methods.normalizeToggleValue(desiredLiteral)

        end

        if methods.startupAutoRunCacheInitialized() then

            return methods.startupAutoRunCachedValue()

        end

        return fallback

    end


    function methods.hydrateStartupAutoRunFieldFromCache()

        local field = methods.getField('startupAutoRun')

        if not field or not methods.startupAutoRunCacheInitialized() then

            return false

        end

        methods.setFieldSessionValue(field, methods.startupAutoRunCachedValue())

        return true

    end



    function methods.probeStartupAutoRunField()

        local field = methods.getField('startupAutoRun')

        if not field then

            return '0'

        end

        local actualLiteral = methods.resolveStartupAutoRunState(nil)

        methods.setFieldSessionValue(field, actualLiteral)

        return actualLiteral

    end


    function methods.readRuntimeState(targetId)

        local core = methods.responsiveLayoutCore()

        if not core or not core.GetLiveState then

            return nil

        end

        return core.GetLiveState(SKIN, targetId)

    end



    function methods.writeIniVariable(path, variableName, value)

        local resolved = tostring(value or '')

        setVariable(variableName, resolved)

        SKIN:Bang('!WriteKeyValue', 'Variables', variableName, resolved, path)

    end



    function methods.writeIniKeyValue(path, sectionName, keyName, value)

        if not path or path == '' or not sectionName or sectionName == '' or not keyName or keyName == '' then

            return

        end

        SKIN:Bang('!WriteKeyValue', sectionName, keyName, tostring(value or ''), path)

    end



    function methods.settingsFilePath(fileKey)

        methods.ensurePaths()

        if fileKey == 'State' then

            return methods.statePath()

        end

        return state.settingsRoot .. schema.settingsFiles[fileKey]

    end



    function methods.settingsIniPath()

        return trim(SKIN:GetVariable('CURRENTPATH', '')) .. 'Settings.ini'

    end



    function methods.readSettingsMetadataVersion()

        if state.settingsMetadataVersion ~= nil then

            return state.settingsMetadataVersion

        end



        local resolved = trim(SKIN:GetVariable('AppVersion', ''))
        if resolved == '' then
            resolved = trim(SKIN:GetVariable('Version', ''))
        end

        if resolved == '' then

            local path = methods.settingsIniPath()

            local handle = io.open(path, 'rb')

            if handle then

                local bytes = handle:read('*all') or ''

                handle:close()

                local marker = 'V\0e\0r\0s\0i\0o\0n\0=\0'

                local startIndex = bytes:find(marker, 1, true)

                if startIndex then

                    local cursor = startIndex + #marker

                    local fragments = {}

                    while cursor <= #bytes do

                        local low = bytes:byte(cursor)

                        local high = bytes:byte(cursor + 1)

                        if not low or not high or low == 0x0D or low == 0x0A then

                            break

                        end

                        fragments[#fragments + 1] = string.char(low)

                        cursor = cursor + 2

                    end

                    resolved = trim(table.concat(fragments))

                end

            end

        end



        state.settingsMetadataVersion = resolved

        return resolved

    end



    function methods.appVersionDisplayValue()

        local resolved = methods.readSettingsMetadataVersion()

        if trim(resolved) == '' then

            return 'v?'

        end

        return 'v' .. resolved

    end



    function methods.readFieldValue(field)

        return trim(SKIN:GetVariable(field.variableName, ''))

    end



    function methods.setFieldSessionValue(field, value)

        if not field then

            return

        end

        setVariable(field.variableName, tostring(value or ''))

    end



    function methods.normalizeToggleValue(raw)

        return trim(raw) == '1' and '1' or '0'

    end



    function methods.normalizeIntegerValue(field, raw, fallback)

        local numeric = tonumber(trim(raw))

        if not numeric then

            numeric = tonumber(trim(fallback)) or field.min or 0

        end

        numeric = math.floor(numeric)

        if field.min ~= nil and numeric < field.min then

            numeric = field.min

        end

        if field.max ~= nil and numeric > field.max then

            numeric = field.max

        end

        return tostring(numeric)

    end



    local function clampClockColorChannel(value)

        local numeric = tonumber(value)

        if not numeric then

            return nil

        end

        numeric = math.floor(numeric + 0.5)

        if numeric < 0 then

            numeric = 0

        elseif numeric > 255 then

            numeric = 255

        end

        return numeric

    end



    local function formatClockColorRgba(red, green, blue, alpha)

        return string.format('%d,%d,%d,%d', red, green, blue, alpha)

    end



    local function parseStoredClockColorValue(raw)

        local parts = {}

        for token in string.gmatch(trim(raw), '[^,%s]+') do

            parts[#parts + 1] = token

        end

        if #parts < 3 or #parts > 4 then

            return nil

        end

        local red = clampClockColorChannel(parts[1])

        local green = clampClockColorChannel(parts[2])

        local blue = clampClockColorChannel(parts[3])

        local alpha = clampClockColorChannel(parts[4] or '255')

        if not red or not green or not blue or not alpha then

            return nil

        end

        return formatClockColorRgba(red, green, blue, alpha), red, green, blue, alpha

    end



    local function parseHexClockColorValue(raw)

        local digits = trim(raw):match('^#([%x][%x][%x][%x][%x][%x])$')

        if not digits then

            return nil

        end

        local red = tonumber(digits:sub(1, 2), 16)

        local green = tonumber(digits:sub(3, 4), 16)

        local blue = tonumber(digits:sub(5, 6), 16)

        local alpha = 255

        return formatClockColorRgba(red, green, blue, alpha), red, green, blue, alpha

    end



    function methods.normalizeClockColorValue(raw, fallback)

        local normalized = parseHexClockColorValue(raw)

        if normalized then

            return normalized

        end

        normalized = parseStoredClockColorValue(raw)

        if normalized then

            return normalized

        end

        normalized = parseHexClockColorValue(fallback)

        if normalized then

            return normalized

        end

        normalized = parseStoredClockColorValue(fallback)

        if normalized then

            return normalized

        end

        return '255,255,255,255'

    end



    function methods.displayClockColorValue(raw)

        local _, red, green, blue = parseStoredClockColorValue(raw)

        if red == nil then

            _, red, green, blue = parseHexClockColorValue(raw)

        end

        if red == nil then

            return '#FFFFFF'

        end

        return string.format('#%02X%02X%02X', red, green, blue)

    end



    function methods.isIndicatorLikeField(field)

        return field and (field.dropdownId == 'indicatorSource' or field.dropdownId == 'indicatorExpLevel')

    end



    function methods.pairedDiskTargetField(field)

        if not field or not field.pairedDiskTargetFieldKey then

            return nil

        end

        return methods.getField(field.pairedDiskTargetFieldKey)

    end



    function methods.currentDiskTargetForField(field)

        local targetField = methods.pairedDiskTargetField(field)

        if not targetField then

            return ''

        end

        return trim(methods.readFieldValue(targetField))

    end



    function methods.normalizeClockDisplayModeValue(raw)
        local normalized = string.lower(trim(raw))
        if normalized == 'text' or normalized == 'sprite' then
            return normalized
        end
        return 'default'
    end

    function methods.normalizeFieldValue(field, raw, fallback)

        if field.valueType == 'bool' then

            return methods.normalizeToggleValue(raw)

        end

        if field.valueType == 'integer' then

            return methods.normalizeIntegerValue(field, raw, fallback)

        end

        if field and field.key == 'clockType' then
            return methods.normalizeClockDisplayModeValue(raw)
        end
        if field and (field.key == 'clockTextColor' or field.key == 'hotbarTextColor') then

            return methods.normalizeClockColorValue(raw, fallback)

        end

        return methods.normalizeTextAliasInput(field, raw)

    end



    function methods.collectFieldTargets(targetSet, field)

        for _, targetName in ipairs(field.refreshTargets or {}) do

            targetSet[targetName] = true

        end

    end



    function methods.refreshTargets(targetSet, options)

        local refreshOptions = options or {}

        if targetSet and refreshOptions.includeSettings == nil then
            refreshOptions.includeSettings = targetSet.__includeSettings == true
        end

        if targetSet and trim(refreshOptions.loadingText or '') == '' then
            refreshOptions.loadingText = targetSet.__loadingText
        end

        if methods.QueueRefreshTargets then

            local shouldRenderSettings = refreshOptions.includeSettings == true or trim(refreshOptions.loadingText or '') ~= ''

            if trim(refreshOptions.loadingText or '') ~= '' then
                methods.setLoadingVisible(true, refreshOptions.loadingText)
            end

            if shouldRenderSettings then
                methods.renderActivePage()
            end

            local queued = methods.QueueRefreshTargets(targetSet, refreshOptions)

            if not queued then
                if trim(refreshOptions.loadingText or '') ~= '' then
                    methods.setLoadingVisible(false)
                end
                if shouldRenderSettings then
                    methods.renderActivePage()
                end
            end

            return

        end

        methods.ensurePaths()

        for targetName, _ in pairs(targetSet or {}) do

            if targetName ~= 'Settings' then

                local target = schema.refreshTargetsByName[targetName]

                if target and state.rootConfig ~= '' then

                    local configPath = state.rootConfig .. '\\' .. target.config

                    local isActive = methods.isConfigTargetActive(targetName)

                    if isActive then

                        if targetName == 'Inventory' then

                            SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'PrepareInventoryRefreshPosition()', configPath)

                        else

                            SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'CaptureLiveStateNow()', configPath)

                        end

                        SKIN:Bang('!Refresh', configPath, target.file)

                    end

                end

            end

        end

    end


    function methods.activationSemanticValue(field, resolved)

        if not field then

            return nil

        end

        local activateTargets = field.activateTargets or {}

        local deactivateTargets = field.deactivateTargets or activateTargets

        if #activateTargets == 0 and #deactivateTargets == 0 then

            return nil

        end

        if field.valueType == 'bool' then

            return methods.normalizeToggleValue(resolved) == '1'

        end

        if field.dropdownId == 'indicatorSource' then

            return trim(resolved) ~= 'disabled'

        end

        return nil

    end



    function methods.activateConfigTarget(targetName)

        methods.ensurePaths()

        if not targetName or targetName == '' or state.rootConfig == '' then

            return

        end

        local target = schema.refreshTargetsByName[targetName]

        if target then

            SKIN:Bang('!ActivateConfig', state.rootConfig .. '\\' .. target.config, target.file)

        end

    end



    function methods.deactivateConfigTarget(targetName)

        methods.ensurePaths()

        if not targetName or targetName == '' or state.rootConfig == '' then

            return

        end

        local target = schema.refreshTargetsByName[targetName]

        if target then

            SKIN:Bang('!DeactivateConfig', state.rootConfig .. '\\' .. target.config)

        end

    end



    function methods.syncFieldActivationState(field, resolved)

        local activateTargets = field and field.activateTargets or {}

        local deactivateTargets = field and field.deactivateTargets or activateTargets

        local shouldActivate = methods.activationSemanticValue(field, resolved)

        if shouldActivate == nil then

            return nil

        end

        local targetList = shouldActivate and activateTargets or deactivateTargets

        for _, targetName in ipairs(targetList) do

            if shouldActivate then

                methods.activateConfigTarget(targetName)

            else

                methods.deactivateConfigTarget(targetName)

            end

        end

        return shouldActivate

    end



    function methods.captureSnapshot()

        local snapshot = {}

        for _, fieldKey in ipairs(schema.trackedFieldKeys) do

            local field = methods.getField(fieldKey)

            snapshot[fieldKey] = methods.normalizeFieldValue(field, methods.readFieldValue(field), '')

        end

        local snapshotMinecraftSkinImagePath = SKIN:GetVariable('MinecraftSkinImagePath', '')
        local snapshotMinecraftSkinImagePathVerified = methods.isMinecraftSkinImagePathVerified(snapshotMinecraftSkinImagePath)
        snapshot.minecraftSkinImagePath = methods.resolveStoredMinecraftSkinImagePath(snapshot.minecraftSkinUsername, snapshotMinecraftSkinImagePath, { allowStoredWidePath = snapshotMinecraftSkinImagePathVerified })
        snapshot.minecraftSkinImagePathVerified = snapshot.minecraftSkinImagePath ~= '' and (snapshotMinecraftSkinImagePathVerified or methods.isPngFile(snapshot.minecraftSkinImagePath)) and '1' or '0'

        return snapshot

    end



    function methods.toggleSemanticValue(field, storedValue)

        local storedEnabled = methods.normalizeToggleValue(storedValue) == '1'

        if field.invert then

            return not storedEnabled

        end

        return storedEnabled

    end



    function methods.nextStoredToggleValue(field)

        local nextSemantic = not methods.toggleSemanticValue(field, methods.readFieldValue(field))

        if field.invert then

            return nextSemantic and '0' or '1'

        end

        return nextSemantic and '1' or '0'

    end



    function methods.defaultSnapshotFallbackValue(fieldKey)

        local fallbackByFieldKey = {

            hotbarDragSnap = '0',

            indicatorsDragSnap = '0',

            inventoryDragSnap = '0',

            clockDragSnap = '0',

        }

        return fallbackByFieldKey[fieldKey]

    end

    function methods.defaultSnapshotRestoreValue(fieldKey, rawValue)

        local field = methods.getField(fieldKey)

        local resolved = methods.normalizeFieldValue(field, rawValue, rawValue)

        if field and field.valueType == 'bool' and field.defaultSnapshotInvert then

            return resolved == '1' and '0' or '1'

        end

        return resolved

    end


    function methods.loadDefaultSnapshot(fieldKeys)

        local snapshot = {}

        local missingKeys = {}

        local sentinel = '__SETTINGS_DEFAULT_MISSING__'

        for _, fieldKey in ipairs(fieldKeys or schema.trackedFieldKeys) do

            local variableName = 'SettingsDefault_' .. fieldKey

            local value = SKIN:GetVariable(variableName, sentinel)

            if value == sentinel then

                local fallback = methods.defaultSnapshotFallbackValue(fieldKey)

                if fallback ~= nil then

                    snapshot[fieldKey] = methods.defaultSnapshotRestoreValue(fieldKey, fallback)

                else

                    missingKeys[#missingKeys + 1] = fieldKey

                end
            else

                snapshot[fieldKey] = methods.defaultSnapshotRestoreValue(fieldKey, value or '')

            end

        end

        if #missingKeys > 0 then

            return nil, missingKeys

        end

        return snapshot, nil

    end



    function methods.resetFieldKeysForTab(tabId)

        local orderedFieldKeys = {}

        local included = {}

        for _, fieldKey in ipairs(schema.trackedFieldKeys) do

            local field = methods.getField(fieldKey)

            if field and field.tabId == tabId and field.controlType ~= 'action' then

                if not included[field.key] then

                    orderedFieldKeys[#orderedFieldKeys + 1] = field.key

                    included[field.key] = true

                end

                local pairedField = methods.pairedDiskTargetField(field)

                if pairedField and not included[pairedField.key] then

                    orderedFieldKeys[#orderedFieldKeys + 1] = pairedField.key

                    included[pairedField.key] = true

                end

            end

        end

        return orderedFieldKeys

    end



    function methods.copyLayoutTargetIds(targetIds)

        local copied = {}

        for _, id in ipairs(targetIds or {}) do

            copied[#copied + 1] = id

        end

        return copied

    end



    function methods.layoutTargetIdsForTab(tabId)

        local core = methods.responsiveLayoutCore()

        return methods.copyLayoutTargetIds(core.TargetIdsForTab(tabId) or {})

    end



    function methods.allLayoutTargetIds()

        local core = methods.responsiveLayoutCore()

        return methods.copyLayoutTargetIds(core.AllSkinIds() or {})

    end



    function methods.copyLayoutSnapshot(snapshot)

        local copied = {}

        for id, stateSnapshot in pairs(snapshot or {}) do

            copied[id] = shallowCopy(stateSnapshot)

        end

        return copied

    end



    function methods.captureLayoutSnapshot(targetIds)

        local core = methods.responsiveLayoutCore()

        local snapshot = {}

        for _, id in ipairs(targetIds or {}) do

            local stateSnapshot = core.GetState(SKIN, id)

            if stateSnapshot then

                snapshot[id] = shallowCopy(stateSnapshot)

            end

        end

        return snapshot

    end



    function methods.captureTabLayoutSnapshot(tabId)

        return methods.captureLayoutSnapshot(methods.layoutTargetIdsForTab(tabId))

    end



    function methods.captureAllLayoutSnapshot()

        return methods.captureLayoutSnapshot(methods.allLayoutTargetIds())

    end



    function methods.captureBaselineState()

        state.baselineSnapshot = methods.captureSnapshot()

        state.baselineLayoutTargetIds = methods.allLayoutTargetIds()

        state.baselineLayoutSnapshot = methods.captureLayoutSnapshot(state.baselineLayoutTargetIds)

    end



    function methods.layoutSnapshotSignature(snapshot)

        local fragments = {}

        for id, stateSnapshot in pairs(snapshot or {}) do

            local stateFragments = {}

            for key, value in pairs(stateSnapshot or {}) do

                stateFragments[#stateFragments + 1] = key .. '=' .. tostring(value)

            end

            table.sort(stateFragments)

            fragments[#fragments + 1] = id .. '{' .. table.concat(stateFragments, ',') .. '}'

        end

        table.sort(fragments)

        return table.concat(fragments, '|')

    end



    function methods.reflowLayoutTargetIds(targetIds, options)

        local core = methods.responsiveLayoutCore()

        local reflowIds = {}

        local applySettingsLayout = false

        local forceRefresh = options and options.forceRefresh == true

        for _, id in ipairs(targetIds or {}) do

            if id == 'Settings' then

                applySettingsLayout = true

            elseif forceRefresh or methods.isConfigTargetActive(id) then

                reflowIds[#reflowIds + 1] = id

            else

                -- Persist state for inactive targets, but never refresh them from Settings-side reflow.

            end

        end

        if #reflowIds > 0 then

            core.ReflowTargets(SKIN, reflowIds, { forceRefresh = forceRefresh })

        end

        if applySettingsLayout then

            SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()')

        end

    end



    function methods.restoreLayoutSnapshot(snapshot, targetIds)

        local core = methods.responsiveLayoutCore()

        local ids = methods.copyLayoutTargetIds(targetIds)

        if #ids == 0 then

            for id, _ in pairs(snapshot or {}) do

                ids[#ids + 1] = id

            end

            table.sort(ids)

        end

        if #ids == 0 then

            return

        end

        for _, id in ipairs(ids) do

            local stateSnapshot = snapshot and snapshot[id]

            if stateSnapshot then

                core.WriteState(SKIN, id, stateSnapshot, true)

            end

        end

        methods.reflowLayoutTargetIds(ids)

    end



    function methods.restoreTabLayoutSnapshot(tabId, snapshot)

        methods.restoreLayoutSnapshot(snapshot, methods.layoutTargetIdsForTab(tabId))

    end



    function methods.windowOptionTargetIdsForField(field)
        local ids = {}
        for _, targetId in ipairs(field and field.windowOptionTargetIds or {}) do
            ids[#ids + 1] = targetId
        end
        return ids
    end
    function methods.windowOptionNameForField(field)
        if not field then
            return ''
        end
        return trim(field.windowOptionName or '')
    end
    function methods.isWindowOptionToggleField(field)
        local optionName = methods.windowOptionNameForField(field)
        if optionName == '' then
            return false
        end
        return #methods.windowOptionTargetIdsForField(field) > 0
    end
    function methods.isConfigTargetActive(targetName)

        methods.ensurePaths()

        local target = schema.refreshTargetsByName[targetName]

        if not target or state.rootConfig == '' then

            return false

        end

        local liveState = methods.readRuntimeState(targetName)

        return liveState ~= nil and liveState.Active or false

    end



    function methods.syncWindowOptionToggleState(field, resolved)
        if not methods.isWindowOptionToggleField(field) then
            return false
        end
        methods.ensurePaths()
        local literal = methods.normalizeToggleValue(resolved) == '1' and '1' or '0'
        local optionName = methods.windowOptionNameForField(field)
        for _, targetName in ipairs(methods.windowOptionTargetIdsForField(field)) do
            if methods.isConfigTargetActive(targetName) then
                local target = schema.refreshTargetsByName[targetName]
                local configPath = state.rootConfig .. '\\' .. target.config
                SKIN:Bang('!SetVariable', field.variableName, literal, configPath)
                SKIN:Bang('!' .. optionName, literal, configPath)
            end
        end
        return true
    end

    function methods.syncHotbarInventoryEnabledLiveState(field, resolved)
        if not field or field.key ~= 'inventoryEnabled' then
            return false
        end
        methods.ensurePaths()
        if not methods.isConfigTargetActive('Hotbar') then
            return false
        end
        local target = schema.refreshTargetsByName.Hotbar
        if not target then
            return false
        end
        local configPath = state.rootConfig .. '\\' .. target.config
        SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), configPath)
        SKIN:Bang('!CommandMeasure', 'MeasureHotbarLayout', 'ApplyLayout()', configPath)
        SKIN:Bang('!CommandMeasure', 'MeasureZPosArrangement', 'ApplyHotbar()', configPath)
        return true
    end

    function methods.syncInventoryTooltipSize(field, resolved)

        if not field or field.key ~= 'inventoryTooltipSize' then

            return false

        end

        methods.ensurePaths()

        local core = methods.responsiveLayoutCore()

        local scale = (core and core.GetScale and tonumber(core.GetScale(SKIN))) or 1

        local numericResolved = tonumber(resolved) or tonumber(field.min) or 8

        local scaledValue = tostring(math.max(8, math.floor((numericResolved * scale) + 0.5)))

        setVariable('ResponsiveBase_' .. field.variableName, tostring(resolved))

        if methods.isConfigTargetActive('Inventory') then

            local target = schema.refreshTargetsByName.Inventory

            if target then

                local configPath = state.rootConfig .. '\\' .. target.config

                SKIN:Bang('!SetVariable', 'ResponsiveBase_' .. field.variableName, tostring(resolved), configPath)

                SKIN:Bang('!SetVariable', field.variableName, scaledValue, configPath)

                SKIN:Bang('!SetOption', 'MeterText', 'FontSize', scaledValue, configPath)

                SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RefreshCurrentTooltip()', configPath)

                SKIN:Bang('!Redraw', configPath)

            end

        end

        return true

    end



    function methods.syncInventoryItemSize(field, resolved)

        if not field or field.key ~= 'inventoryItemSize' then

            return false

        end

        methods.ensurePaths()

        setVariable('ResponsiveBase_' .. field.variableName, tostring(resolved))

        if methods.isConfigTargetActive('Inventory') then

            local target = schema.refreshTargetsByName.Inventory

            if target then

                local configPath = state.rootConfig .. '\\' .. target.config

                SKIN:Bang('!SetVariable', 'ResponsiveBase_' .. field.variableName, tostring(resolved), configPath)

                SKIN:Bang('!CommandMeasure', 'MeasureResponsiveLayout', 'ApplyLayout()', configPath)

                SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', 'InitInfos()', configPath)

                SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'ResetInteractionState()', configPath)

                SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'SyncSelectedSlotHighlight()', configPath)

                SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RefreshHoveredInfo()', configPath)

                SKIN:Bang('!Redraw', configPath)

            end

        end

        return true

    end



    function methods.syncInventorySupportToggle(field, resolved)

        local meterByKey = {

            hideUsageGuide = { 'MeterOpenInfo' },

            hideSkinFolderButton = { 'MeterOpenSkinFolder' },

            hideEditButton = { 'MeterEdit' },

            hideSettingsButton = { 'MeterSettingsUIButton' },

            hideSteve = { 'MeterPlayerDefault', 'MeterPlayerCustom' },

        }

        local meterNames = meterByKey[field and field.key or '']

        if not meterNames then

            return false

        end

        methods.ensurePaths()

        if methods.isConfigTargetActive('Inventory') then

            local target = schema.refreshTargetsByName.Inventory

            if target then

                local configPath = state.rootConfig .. '\\' .. target.config

                SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), configPath)

                for _, meterName in ipairs(meterNames) do

                    SKIN:Bang('!UpdateMeter', meterName, configPath)

                end

                if field.key == 'hideSteve' then

                    SKIN:Bang('!UpdateMeasure', 'MeasurePlayerDefaultHidden', configPath)

                    SKIN:Bang('!UpdateMeasure', 'MeasurePlayerCustomHidden', configPath)

                    SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'LeaveOptionHover()', configPath)

                end

                SKIN:Bang('!Redraw', configPath)

            end

        end

        return true

    end
    function methods.syncInventoryPlayerSkinLiveState(username, imagePath, targetSet, options)

        methods.ensurePaths()

        options = options or {}

        local allowStoredWidePath = options.verified == true or methods.isMinecraftSkinImagePathVerified(imagePath)

        local resolvedImagePath = methods.resolveStoredMinecraftSkinImagePath(username, imagePath, { allowStoredWidePath = allowStoredWidePath })

        local resolvedImagePathVerified = resolvedImagePath ~= '' and (allowStoredWidePath or methods.isPngFile(resolvedImagePath))

        if not methods.isConfigTargetActive('Inventory') then

            return false

        end

        local target = schema.refreshTargetsByName.Inventory

        if not target then

            return false

        end

        local configPath = state.rootConfig .. '\\' .. target.config

        SKIN:Bang('!SetVariable', 'MinecraftSkinUsername', tostring(username or ''), configPath)

        SKIN:Bang('!SetVariable', 'MinecraftSkinImagePath', resolvedImagePath, configPath)

        SKIN:Bang('!SetVariable', 'MinecraftSkinImagePathVerified', resolvedImagePathVerified and '1' or '0', configPath)

        SKIN:Bang('!CommandMeasure', 'MeasurePlayerSkinState', 'Sync()', configPath)

        SKIN:Bang('!UpdateMeasure', 'MeasurePlayerDefaultHidden', configPath)

        SKIN:Bang('!UpdateMeasure', 'MeasurePlayerCustomHidden', configPath)

        SKIN:Bang('!UpdateMeter', 'MeterPlayerDefault', configPath)

        SKIN:Bang('!UpdateMeter', 'MeterPlayerCustom', configPath)

        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'LeaveOptionHover()', configPath)

        SKIN:Bang('!Redraw', configPath)

        if targetSet then

            targetSet.Inventory = nil

        end

        return true

    end





    function methods.syncInventoryBottomRowLiveState(field, resolved, targetSet)

        if not field or field.key ~= 'inventoryBottomRow' then

            return false

        end

        methods.ensurePaths()

        if not methods.isConfigTargetActive('Inventory') then

            return false

        end

        local target = schema.refreshTargetsByName.Inventory

        if not target then

            return false

        end

        local configPath = state.rootConfig .. '\\' .. target.config

        SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), configPath)

        SKIN:Bang('!CommandMeasure', 'MeasureItemInfoInitializer', 'InitInfos()', configPath)

        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'ResetInteractionState()', configPath)

        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'SyncSelectedSlotHighlight()', configPath)

        SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'RefreshHoveredInfo()', configPath)

        SKIN:Bang('!Redraw', configPath)

        local hotbarTarget = schema.refreshTargetsByName.Hotbar
        if hotbarTarget and methods.isConfigTargetActive('Hotbar') then
            local hotbarConfigPath = state.rootConfig .. '\\' .. hotbarTarget.config
            local inventoryState = methods.readRuntimeState('Inventory')

            SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), hotbarConfigPath)

            if inventoryState then
                SKIN:Bang('!SetVariable', 'ResponsiveLayout_Inventory_LiveActive', inventoryState.Active and '1' or '0', hotbarConfigPath)
                if inventoryState.WindowX ~= nil then
                    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Inventory_LiveWindowX', tostring(inventoryState.WindowX), hotbarConfigPath)
                end
                if inventoryState.WindowY ~= nil then
                    SKIN:Bang('!SetVariable', 'ResponsiveLayout_Inventory_LiveWindowY', tostring(inventoryState.WindowY), hotbarConfigPath)
                end
            end

            SKIN:Bang('!CommandMeasure', 'MeasureHighlight', 'SyncHotbarEditorZPosNow()', hotbarConfigPath)
        end

        if targetSet then

            targetSet.Inventory = nil

        end

        return true

    end



    function methods.isClockHideMeridiemField(field)

        return field ~= nil and (field.key == 'clockHideMeridiem' or field.variableName == 'HideClockMeridiem')

    end



    function methods.clockLiveMeterNames()

        return { 'MeterTime24', 'MeterDate24', 'MeterTime12', 'MeterDate12', 'MeterTime12NoMeridiem', 'MeterDate12NoMeridiem' }

    end



    function methods.readClockDisplayModeLiteral()
        local field = methods.getField('clockType')
        if field then
            return methods.normalizeClockDisplayModeValue(methods.readFieldValue(field))
        end
        return methods.normalizeClockDisplayModeValue(SKIN:GetVariable('ClockDisplayMode', 'default'))
    end

    function methods.clockSurfaceEnabledForMode(targetName, mode, globalEnabled)
        if methods.normalizeToggleValue(globalEnabled) ~= '1' then
            return false
        end
        local normalizedMode = methods.normalizeClockDisplayModeValue(mode)
        if targetName == 'Clock' then
            return normalizedMode ~= 'sprite'
        end
        if targetName == 'ClockSprite' then
            return normalizedMode ~= 'text'
        end
        return false
    end

    function methods.readClockGlobalEnabledLiteral()
        local field = methods.getField('clockEnabled')
        if field then
            return methods.normalizeToggleValue(methods.readFieldValue(field))
        end
        return methods.normalizeToggleValue(SKIN:GetVariable('EnableClockSkin', '1'))
    end

    function methods.syncClockSurfaceActivation(mode, globalEnabled)
        local normalizedMode = methods.normalizeClockDisplayModeValue(mode)
        local enabledLiteral = methods.normalizeToggleValue(globalEnabled)
        local textEnabled = normalizedMode == 'sprite' and '0' or '1'
        local spriteEnabled = normalizedMode == 'text' and '0' or '1'
        methods.writeIniVariable(methods.settingsFilePath('Clock'), 'EnableClockTextSkin', textEnabled)
        methods.writeIniVariable(methods.settingsFilePath('Clock'), 'EnableClockSpriteSkin', spriteEnabled)
        setVariable('EnableClockTextSkin', textEnabled)
        setVariable('EnableClockSpriteSkin', spriteEnabled)
        for _, targetName in ipairs({ 'Clock', 'ClockSprite' }) do
            local target = schema.refreshTargetsByName[targetName]
            if target then
                if methods.clockSurfaceEnabledForMode(targetName, normalizedMode, enabledLiteral) then
                    methods.activateConfigTarget(targetName)
                else
                    methods.deactivateConfigTarget(targetName)
                end
            end
        end
    end

    function methods.syncClockType(field, resolved)
        if not field or field.key ~= 'clockType' then
            return false
        end
        methods.syncClockSurfaceActivation(resolved, methods.readClockGlobalEnabledLiteral())
        return true
    end

    function methods.syncClockSpriteSize(field, resolved)
        if not field or field.key ~= 'clockSpriteSize' then
            return false
        end
        methods.ensurePaths()
        setVariable('ResponsiveBase_' .. field.variableName, tostring(resolved))
        if methods.isConfigTargetActive('ClockSprite') then
            local target = schema.refreshTargetsByName.ClockSprite
            if target then
                local configPath = state.rootConfig .. '\\' .. target.config
                SKIN:Bang('!SetVariable', 'ResponsiveBase_' .. field.variableName, tostring(resolved), configPath)
                SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), configPath)
                SKIN:Bang('!UpdateMeter', 'MeterClockSprite', configPath)
                SKIN:Bang('!Redraw', configPath)
            end
        end
        return true
    end

    function methods.readClockHideMeridiemLiteral()

        local field = methods.getField('clockHideMeridiem')

        if field then

            return methods.normalizeToggleValue(methods.readFieldValue(field))

        end

        return methods.normalizeToggleValue(SKIN:GetVariable('HideClockMeridiem', '0'))

    end



    function methods.syncClock24Hour(field, resolved)

        if not field or field.key ~= 'clock24Hour' then

            return false

        end

        methods.ensurePaths()

        if methods.isConfigTargetActive('Clock') then

            local target = schema.refreshTargetsByName.Clock

            if target then

                local configPath = state.rootConfig .. '\\' .. target.config

                local literal = methods.normalizeToggleValue(resolved)

                SKIN:Bang('!SetVariable', field.variableName, literal, configPath)

                for _, meterName in ipairs(methods.clockLiveMeterNames()) do

                    SKIN:Bang('!UpdateMeter', meterName, configPath)

                end

                SKIN:Bang('!Redraw', configPath)

            end

        end

        return true

    end



    function methods.syncClockHideMeridiem(field, resolved)

        if not methods.isClockHideMeridiemField(field) then

            return false

        end

        methods.ensurePaths()

        if methods.isConfigTargetActive('Clock') then

            local target = schema.refreshTargetsByName.Clock

            if target then

                local configPath = state.rootConfig .. '\\' .. target.config

                local literal = methods.normalizeToggleValue(resolved)

                SKIN:Bang('!SetVariable', 'HideClockMeridiem', literal, configPath)

                SKIN:Bang('!UpdateMeasure', 'MeasureTime12', configPath)

                SKIN:Bang('!UpdateMeasure', 'MeasureTime12NoMeridiem', configPath)

                SKIN:Bang('!UpdateMeter', 'MeterTime12', configPath)

                SKIN:Bang('!UpdateMeter', 'MeterTime12NoMeridiem', configPath)

                SKIN:Bang('!Redraw', configPath)

            end

        end

        return true

    end



    function methods.syncClockDateSize(field, resolved)

        if not field or field.key ~= 'clockDateSize' then

            return false

        end

        methods.ensurePaths()

        if methods.isConfigTargetActive('Clock') then

            local target = schema.refreshTargetsByName.Clock

            if target then

                local configPath = state.rootConfig .. '\\' .. target.config

                SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), configPath)

                SKIN:Bang('!UpdateMeter', 'MeterDate24', configPath)

                SKIN:Bang('!UpdateMeter', 'MeterDate12', configPath)

                SKIN:Bang('!UpdateMeter', 'MeterDate12NoMeridiem', configPath)

                SKIN:Bang('!Redraw', configPath)

            end

        end

        return true

    end



    function methods.syncClockTextColor(field, resolved)

        if not field or field.key ~= 'clockTextColor' then

            return false

        end

        methods.ensurePaths()

        if methods.isConfigTargetActive('Clock') then

            local target = schema.refreshTargetsByName.Clock

            if target then

                local configPath = state.rootConfig .. '\\' .. target.config

                SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), configPath)

                for _, meterName in ipairs(methods.clockLiveMeterNames()) do

                    SKIN:Bang('!SetOption', meterName, 'FontColor', tostring(resolved), configPath)

                    SKIN:Bang('!UpdateMeter', meterName, configPath)

                end

                SKIN:Bang('!Redraw', configPath)

            end

        end

        return true

    end



    function methods.syncHotbarTextColor(field, resolved)

        if not field or field.key ~= 'hotbarTextColor' then

            return false

        end

        methods.ensurePaths()

        if methods.isConfigTargetActive('Hotbar') then

            local target = schema.refreshTargetsByName.Hotbar

            if target then

                local configPath = state.rootConfig .. '\\' .. target.config

                SKIN:Bang('!SetVariable', field.variableName, tostring(resolved), configPath)

                SKIN:Bang('!CommandMeasure', 'MeasureFade', 'RefreshBaseColor()', configPath)

                SKIN:Bang('!UpdateMeter', 'MeterHotbarText', configPath)

                SKIN:Bang('!Redraw', configPath)

            end

        end

        return true

    end



    function methods.syncClockActivationResync(field, shouldActivate)

        if not field or field.key ~= 'clockEnabled' then

            return false

        end

        methods.syncClockSurfaceActivation(methods.readClockDisplayModeLiteral(), shouldActivate and '1' or '0')

        if shouldActivate ~= true then

            return true

        end

        methods.ensurePaths()

        local target = schema.refreshTargetsByName.Clock

        local clock24HourField = methods.getField('clock24Hour')

        local clockTextColorField = methods.getField('clockTextColor')

        local clockHideMeridiemLiteral = methods.readClockHideMeridiemLiteral()

        if not target or not clock24HourField or not clockTextColorField then

            return false

        end

        local configPath = state.rootConfig .. '\\' .. target.config

        local literal = methods.normalizeToggleValue(methods.readFieldValue(clock24HourField))

        local colorLiteral = methods.normalizeStoredClockColorValue(methods.readFieldValue(clockTextColorField), '255,255,255,255')

        SKIN:Bang('!SetVariable', clock24HourField.variableName, literal, configPath)

        SKIN:Bang('!SetVariable', 'HideClockMeridiem', clockHideMeridiemLiteral, configPath)

        SKIN:Bang('!UpdateMeasure', 'MeasureTime12', configPath)

        SKIN:Bang('!UpdateMeasure', 'MeasureTime12NoMeridiem', configPath)

        for _, meterName in ipairs(methods.clockLiveMeterNames()) do

            SKIN:Bang('!SetOption', meterName, 'FontColor', colorLiteral, configPath)

            SKIN:Bang('!UpdateMeter', meterName, configPath)

        end

        SKIN:Bang('!Redraw', configPath)

        return true

    end



    function methods.liveWindowPositionForTargetId(targetId, fallbackRects)

        methods.ensurePaths()

        local target = schema.refreshTargetsByName[targetId]

        if not target or state.rootConfig == '' then

            return nil

        end

        local core = methods.responsiveLayoutCore()

        if core and core.LiveWindowPositionForId then

            return core.LiveWindowPositionForId(SKIN, targetId, fallbackRects)

        end

        local fallback = fallbackRects and fallbackRects[targetId]

        if fallback then

            return { x = fallback.x, y = fallback.y }

        end

        return nil

    end



    function methods.captureFixedPositionsForIds(ids)

        local core = methods.responsiveLayoutCore()

        local rects = core.ResolveRects(SKIN)

        local positionsById = {}

        for _, id in ipairs(ids or {}) do

            local position = methods.liveWindowPositionForTargetId(id, rects)

            if position then

                positionsById[id] = position

            end

        end

        core.CaptureFixedPositionsForIds(SKIN, ids, positionsById)

    end



    function methods.ResetTabPositionsToDefaults(tabId)

        local ids = methods.layoutTargetIdsForTab(tabId)

        if #ids == 0 then

            return false

        end

        local core = methods.responsiveLayoutCore()

        core.ResetStateIds(SKIN, ids)

        methods.reflowLayoutTargetIds(ids, { forceRefresh = true })

        return true

    end



    function methods.ResetAllSkinPositions()

        local ids = methods.allLayoutTargetIds()

        if #ids == 0 then

            return false

        end

        local core = methods.responsiveLayoutCore()

        core.ResetStateIds(SKIN, ids)

        methods.reflowLayoutTargetIds(ids, { forceRefresh = true })

        return true

    end



    function methods.ResetTabToDefaults(tabId, historyLabel, options)

        options = options or {}

        local fieldKeys = methods.resetFieldKeysForTab(tabId)

        local defaultSnapshot, missingKeys = methods.loadDefaultSnapshot(fieldKeys)

        if not defaultSnapshot then

            logNotice('Settings default snapshot is incomplete for tab reset: ' .. table.concat(missingKeys or {}, ', '))


            return false

        end

        local beforeSnapshot = methods.captureSnapshot()

        local targets = {}

        for _, fieldKey in ipairs(fieldKeys) do

            local field = methods.getField(fieldKey)

            local desired = defaultSnapshot[fieldKey]

            if field and field.controlType ~= 'action' and desired ~= nil then

                methods.applyFieldValue(field, desired, { targetSet = targets })

            end

        end

        local afterSnapshot = methods.captureSnapshot()

        local changed = app.snapshotSignature(beforeSnapshot) ~= app.snapshotSignature(afterSnapshot)

        if not changed then

            return false

        end

        methods.refreshTargets(targets)

        if not options.suppressHistory then

            methods.pushHistory(historyLabel, beforeSnapshot, { afterSnapshot = afterSnapshot })

        end

        return true

    end



    function methods.pushHistory(label, beforeSnapshot, options)

        options = options or {}

        local afterSnapshot = options.afterSnapshot or methods.captureSnapshot()

        local beforeLayout = options.beforeLayout

        local afterLayout = options.afterLayout

        local snapshotChanged = app.snapshotSignature(beforeSnapshot) ~= app.snapshotSignature(afterSnapshot)

        local layoutChanged = false

        if beforeLayout or afterLayout then

            layoutChanged = methods.layoutSnapshotSignature(beforeLayout) ~= methods.layoutSnapshotSignature(afterLayout)

        end

        if not snapshotChanged and not layoutChanged then

            return false

        end

        local entry = {

            label = label,

            before = shallowCopy(beforeSnapshot),

            after = shallowCopy(afterSnapshot),

        }

        if options.tabId then

            entry.tabId = options.tabId

        end

        if beforeLayout or afterLayout then

            entry.beforeLayout = methods.copyLayoutSnapshot(beforeLayout)

            entry.afterLayout = methods.copyLayoutSnapshot(afterLayout)

            entry.layoutTargetIds = methods.copyLayoutTargetIds(options.layoutTargetIds)

        end

        state.undoHistory[#state.undoHistory + 1] = entry

        state.redoHistory = {}

        return true

    end



    function methods.applyFieldValue(field, value, options)

        options = options or {}

        local currentValue = methods.readFieldValue(field)
        if field and field.key == 'language' then
            value = methods.normalizeLanguageCode(value, currentValue)
        end

        local previousResolved = methods.normalizeFieldValue(field, currentValue, currentValue)

        local resolved = methods.normalizeFieldValue(field, value, currentValue)

        if field and field.key == 'startupAutoRun' then

            resolved = methods.resolveStartupAutoRunState(resolved)

            methods.persistStartupAutoRunCache(resolved)

        end

        local selection = nil

        if methods.isIndicatorLikeField(field) then

            selection = options.selectionOption or methods.resolveIndicatorLikeInput(field, value)

            resolved = trim(selection.value or resolved)

        end

        if previousResolved == resolved then

            return false

        end

        if field.sessionOnly then

            methods.setFieldSessionValue(field, resolved)

        elseif field.settingsFile == 'State' then

            methods.writeIniVariable(methods.statePath(), field.variableName, resolved)

            if field.variableName == 'SettingsThemeMode' then

                methods.applyTheme(resolved)

            end

        else

            methods.writeIniVariable(methods.settingsFilePath(field.settingsFile), field.variableName, resolved)

        end

        if field.variableName == 'BaseFont' then

            setVariable('BaseFont', resolved)

        end
        if field.key == 'minecraftSkinUsername' then

            methods.syncMinecraftSkinDraft(resolved)

        end

        if field.key == 'language' then
            methods.syncActiveLocalization(resolved)
            methods.syncItemLabelsForLanguage(resolved)
        end

        if methods.syncWindowOptionToggleState(field, resolved) then
            return
        end

        if methods.syncInventoryTooltipSize(field, resolved) then

            return

        end

        if methods.syncInventoryItemSize(field, resolved) then

            return

        end

        if methods.syncInventorySupportToggle(field, resolved) then

            return

        end

        if methods.syncClockType(field, resolved) then

            return

        end

        if methods.syncClockSpriteSize(field, resolved) then

            return

        end

        if methods.syncClock24Hour(field, resolved) then

            return

        end

        if methods.syncClockHideMeridiem(field, resolved) then

            return

        end

        if methods.syncClockDateSize(field, resolved) then

            return

        end

        if methods.syncClockTextColor(field, resolved) then

            return

        end

        if methods.syncHotbarTextColor(field, resolved) then

            return

        end

        local targetSet = options.targetSet or {}

        methods.collectFieldTargets(targetSet, field)

        methods.syncHotbarInventoryEnabledLiveState(field, resolved)

        methods.syncInventoryBottomRowLiveState(field, resolved, targetSet)

        if selection and selection.diskTarget and field.pairedDiskTargetFieldKey then

            local targetField = methods.getField(field.pairedDiskTargetFieldKey)

            if targetField then

                methods.writeIniVariable(methods.settingsFilePath(targetField.settingsFile), targetField.variableName, trim(selection.diskTarget))

                methods.collectFieldTargets(targetSet, targetField)

            end

        end

        local shouldRefreshActivatedTarget = nil

        if methods.activationSemanticValue(field, previousResolved) ~= methods.activationSemanticValue(field, resolved) then

            shouldRefreshActivatedTarget = methods.syncFieldActivationState(field, resolved)

        end

        methods.syncClockActivationResync(field, shouldRefreshActivatedTarget)

        if shouldRefreshActivatedTarget == false then

            if not field.preserveRefreshTargetsOnDeactivate then

                for _, targetName in ipairs(field.refreshTargets or {}) do

                    targetSet[targetName] = nil

                end

            end

            for _, targetName in ipairs(field.activateTargets or {}) do

                targetSet[targetName] = nil

            end

            for _, targetName in ipairs(field.deactivateTargets or {}) do

                targetSet[targetName] = nil

            end

        end

                local refreshOptions = nil

        if field.key == 'language' then
            local deferLanguageFanout = options.deferLanguageFanout == true
            if deferLanguageFanout then
                for _, targetName in ipairs(field.refreshTargets or {}) do
                    if targetName ~= 'Settings' then
                        targetSet[targetName] = nil
                    end
                end
            end
            targetSet.Settings = true
            refreshOptions = {
                includeSettings = true,
                loadingText = methods.languageSwitchLoadingText(resolved),
                delayTicks = 0,
            }
        end

        if options.targetSet and refreshOptions then
            options.targetSet.__includeSettings = true
            options.targetSet.__loadingText = refreshOptions.loadingText
        end

        if not options.targetSet then

            methods.refreshTargets(targetSet, refreshOptions)

        end

    end



    function methods.restoreSnapshot(snapshot, options)
        options = options or {}
        local targets = {}
        local skipFieldKeySet = {}
        for _, fieldKey in ipairs(options.skipFieldKeys or {}) do
            skipFieldKeySet[fieldKey] = true
        end
        local fieldKeys = options.fieldKeys or schema.trackedFieldKeys
        local restoreMinecraftSkinState = false
        for _, fieldKey in ipairs(fieldKeys) do
            local field = methods.getField(fieldKey)
            local desired = snapshot[fieldKey]
            if fieldKey == 'minecraftSkinUsername' then
                restoreMinecraftSkinState = true
            end
            if not skipFieldKeySet[fieldKey] and field and field.controlType ~= 'action' and desired ~= nil then
                methods.applyFieldValue(field, desired, { targetSet = targets })
            end
        end
        if restoreMinecraftSkinState and not skipFieldKeySet.minecraftSkinUsername and snapshot.minecraftSkinUsername ~= nil then
            local restoredUsername = trim(snapshot.minecraftSkinUsername)
            local snapshotImagePathVerified = trim(snapshot.minecraftSkinImagePathVerified) == '1' or trim(snapshot.minecraftSkinImagePathVerified) == 'true'
            local restoredImagePath = methods.resolveStoredMinecraftSkinImagePath(restoredUsername, snapshot.minecraftSkinImagePath, { allowStoredWidePath = snapshotImagePathVerified })
            local restoredImagePathVerified = restoredImagePath ~= '' and (snapshotImagePathVerified or methods.isPngFile(restoredImagePath))
            local currentUsernameField = methods.getField('minecraftSkinUsername')
            local currentUsername = currentUsernameField and trim(methods.readFieldValue(currentUsernameField)) or ''
            local currentImagePath = trim(SKIN:GetVariable('MinecraftSkinImagePath', ''))
            local currentImagePathVerified = methods.isMinecraftSkinImagePathVerified(currentImagePath)
            local sameUsername = restoredUsername == currentUsername
            local sameImagePath = (restoredImagePath == '' and currentImagePath == '')
                or methods.sameNormalizedPath(currentImagePath, restoredImagePath)
            if not (sameUsername and sameImagePath and currentImagePathVerified == restoredImagePathVerified) then
                methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePath', restoredImagePath)
                methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePathVerified', restoredImagePathVerified and '1' or '0')
                if methods.syncInventoryPlayerSkinLiveState then
                    methods.syncInventoryPlayerSkinLiveState(restoredUsername, restoredImagePath, targets, { verified = restoredImagePathVerified })
                end
            end
        end
        methods.refreshTargets(targets)

        if not options.suppressRender then

            methods.renderActivePage()

        end

        return targets

    end

end







