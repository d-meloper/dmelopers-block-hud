EditorImagePixelationAndPreview = {
    module = nil,
    loadFailed = false,
    pixelator = nil,
    pending = nil,
    strengths = {
        [1] = 2,
        [2] = 3,
        [3] = 4,
    },
    cleanupPendingToken = '',
    cleanupSequence = 0,
    extensions = {
        '.png',
        '.jpg',
        '.jpeg',
        '.jpe',
        '.bmp',
        '.gif',
        '.tif',
        '.tiff',
        '.ico',
        '.jxr',
        '.wdp',
        '.dds',
    },
}

local POWERSHELL_UNAVAILABLE_FALLBACK = 'PowerShell could not be started, so helper features such as icon/image selection, icon pixelation, skin management, and updates may be unavailable. Contact dmeloper@gmail.com for details.'

function EditorImagePixelationAndPreview.bridge()
    return EditorInputCommitPixelBridge or {}
end

function EditorImagePixelationAndPreview.trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

function EditorImagePixelationAndPreview.joinPath(base, leaf)
    base = tostring(base or '')
    leaf = tostring(leaf or '')
    if base == '' then
        return leaf
    end
    if base:sub(-1) == '\\' or base:sub(-1) == '/' then
        return base .. leaf
    end
    return base .. '\\' .. leaf
end

function EditorImagePixelationAndPreview.fileName(path)
    local text = EditorImagePixelationAndPreview.trim(path)
    text = text:gsub('/', '\\')
    return text:match('([^\\]+)$') or text
end

function EditorImagePixelationAndPreview.outputPreview(output, limit)
    output = tostring(output or '')
    limit = tonumber(limit) or 260
    output = output:gsub('[\r\n]+', ' | ')
    if #output > limit then
        return output:sub(1, limit) .. '...'
    end
    return output
end

function EditorImagePixelationAndPreview.runCommandErrorCode(measure)
    if not measure or type(measure.GetValue) ~= 'function' then
        return 0
    end
    return tonumber(measure:GetValue()) or 0
end

function EditorImagePixelationAndPreview.clearPixelatorPending(pixelator)
    if not pixelator then
        return
    end
    pixelator.pendingToken = ''
    pixelator.pendingSignature = ''
    pixelator.pendingOutputPath = ''
    pixelator.pendingSourcePath = ''
    pixelator.queuedRequest = nil
end

function EditorImagePixelationAndPreview.alertPowerShellUnavailable(context)
    local message = tostring(context or 'Editor image pixelation') .. ' failed because PowerShell could not be started. RunCommand error 103.'
    EditorImagePixelationAndPreview.logWarning(message)
    EditorImagePixelationAndPreview.bridge().alert(
        message,
        'ModalAlert_PowerShellUnavailable',
        POWERSHELL_UNAVAILABLE_FALLBACK)
end

function EditorImagePixelationAndPreview.logDebug(message)
    local bridge = EditorImagePixelationAndPreview.bridge()
    if type(bridge.log) == 'function' then
        bridge.log('Debug', tostring(message or ''))
    elseif SKIN then
        SKIN:Bang('!Log', tostring(message or ''), 'Debug')
    end
end

function EditorImagePixelationAndPreview.logWarning(message)
    local bridge = EditorImagePixelationAndPreview.bridge()
    if type(bridge.log) == 'function' then
        bridge.log('Warning', tostring(message or ''))
    elseif SKIN then
        SKIN:Bang('!Log', tostring(message or ''), 'Warning')
    end
end

function EditorImagePixelationAndPreview.userAlert(message)
    message = EditorImagePixelationAndPreview.trim(message)
    if message == '' then
        message = 'Image pixelation failed.'
    end
    local bridge = EditorImagePixelationAndPreview.bridge()
    if bridge and type(bridge.userAlert) == 'function' then
        return bridge.userAlert(message)
    end
    if bridge and type(bridge.alert) == 'function' then
        return bridge.alert(message, '', message)
    end
    return false
end

function EditorImagePixelationAndPreview.localize(key, fallback)
    local bridge = EditorImagePixelationAndPreview.bridge()
    if bridge and type(bridge.localize) == 'function' then
        return bridge.localize(key, fallback)
    end
    return fallback or ''
end

function EditorImagePixelationAndPreview.isGifOrManagedAtlas(value)
    local normalized = EditorImagePixelationAndPreview.trim(value):gsub('/', '\\'):lower()
    local leaf = EditorImagePixelationAndPreview.fileName(normalized)
    if leaf:sub(-4) == '.gif' then
        return true
    end
    if leaf:match('^itemgifatlas_v1_[0-9a-f]+_[0-9a-f]+%.png$') then
        return true
    end
    return normalized:find('\\items\\atlas\\', 1, true) ~= nil
        or normalized:match('^atlas\\') ~= nil
end

function EditorImagePixelationAndPreview.gifUnsupportedMessage()
    local bridge = EditorImagePixelationAndPreview.bridge()
    local languageCode = ''
    if bridge and type(bridge.languageCode) == 'function' then
        languageCode = EditorImagePixelationAndPreview.trim(bridge.languageCode()):lower()
    end
    if languageCode == 'ko-kr' then
        return 'gif 이미지는 픽셀화 기능을 지원하지 않습니다.'
    end
    return 'GIF images do not support pixelation.'
end

function EditorImagePixelationAndPreview.showGifUnsupported()
    local message = EditorImagePixelationAndPreview.gifUnsupportedMessage()
    EditorImagePixelationAndPreview.logWarning(message)
    local bridge = EditorImagePixelationAndPreview.bridge()
    if bridge and type(bridge.unsupportedAlert) == 'function' then
        bridge.unsupportedAlert(message)
    else
        EditorImagePixelationAndPreview.userAlert(message)
    end
    return false
end

function EditorImagePixelationAndPreview.localizedFormat(key, fallback, ...)
    local text = EditorImagePixelationAndPreview.localize(key, fallback)
    local replacements = { ... }
    return tostring(text or ''):gsub('%%(%d+)', function(index)
        local replacement = replacements[tonumber(index)]
        if replacement == nil then
            return ''
        end
        return tostring(replacement)
    end)
end

function EditorImagePixelationAndPreview.stemAndExtension(imageKey)
    local leaf = EditorImagePixelationAndPreview.fileName(imageKey)
    local stem, extension = leaf:match('^(.*)(%.[^%.\\/]*)$')
    if not stem then
        return leaf, ''
    end
    return stem, extension
end

function EditorImagePixelationAndPreview.parseKey(imageKey)
    local stem, extension = EditorImagePixelationAndPreview.stemAndExtension(imageKey)
    if extension:lower() ~= '.png' then
        return {
            stage = 0,
            baseStem = stem,
            originalKey = EditorImagePixelationAndPreview.fileName(imageKey),
        }
    end

    local baseStem, stageText = stem:match('^(.-)_p([123])$')
    if not baseStem or baseStem == '' then
        return {
            stage = 0,
            baseStem = stem,
            originalKey = EditorImagePixelationAndPreview.fileName(imageKey),
        }
    end

    return {
        stage = tonumber(stageText) or 0,
        baseStem = baseStem,
        originalKey = '',
    }
end

function EditorImagePixelationAndPreview.assetKeys()
    local assets = {}
    for entry in EditorImagePixelationAndPreview.trim(SKIN:GetVariable('ItemImageAssets', '')):gmatch('[^|]+') do
        local key = EditorImagePixelationAndPreview.trim(entry)
        if key ~= '' then
            assets[#assets + 1] = EditorImagePixelationAndPreview.fileName(key)
        end
    end
    return assets
end

function EditorImagePixelationAndPreview.extensionPriority(extension)
    extension = tostring(extension or ''):lower()
    for index, candidate in ipairs(EditorImagePixelationAndPreview.extensions) do
        if extension == candidate then
            return index
        end
    end
    return #EditorImagePixelationAndPreview.extensions + 1
end

function EditorImagePixelationAndPreview.findOriginalKey(parsed, currentImageKey)
    if not parsed or parsed.stage < 1 then
        return EditorImagePixelationAndPreview.fileName(currentImageKey)
    end

    local bestKey = ''
    local bestPriority = 1000
    local baseStemLower = tostring(parsed.baseStem or ''):lower()
    for _, assetKey in ipairs(EditorImagePixelationAndPreview.assetKeys()) do
        local stem, extension = EditorImagePixelationAndPreview.stemAndExtension(assetKey)
        if stem:lower() == baseStemLower and not stem:lower():match('_p[123]$') then
            local priority = EditorImagePixelationAndPreview.extensionPriority(extension)
            if priority < bestPriority then
                bestPriority = priority
                bestKey = assetKey
            end
        end
    end
    if bestKey ~= '' then
        return bestKey
    end
    return EditorImagePixelationAndPreview.fileName(currentImageKey)
end

function EditorImagePixelationAndPreview.expectedOriginalKey(parsed, currentImageKey)
    if parsed and parsed.stage >= 1 and EditorImagePixelationAndPreview.trim(parsed.baseStem) ~= '' then
        return EditorImagePixelationAndPreview.fileName(parsed.baseStem .. '.png')
    end
    return EditorImagePixelationAndPreview.fileName(currentImageKey)
end

function EditorImagePixelationAndPreview.missingOriginalMessage(parsed, currentImageKey)
    local expectedKey = EditorImagePixelationAndPreview.expectedOriginalKey(parsed, currentImageKey)
    local expectedPath = EditorImagePixelationAndPreview.itemImagePath(expectedKey)
    if EditorImagePixelationAndPreview.trim(expectedPath) ~= '' then
        return EditorImagePixelationAndPreview.localizedFormat(
            'ModalAlert_EditorPixelateOriginalMissingFile',
            'Missing original source image file: %1',
            expectedPath)
    end
    if expectedKey ~= '' then
        return EditorImagePixelationAndPreview.localizedFormat(
            'ModalAlert_EditorPixelateOriginalMissingAsset',
            'Missing original source image asset: %1',
            expectedKey)
    end
    return EditorImagePixelationAndPreview.localize(
        'ModalAlert_EditorPixelateOriginalMissing',
        'Missing original source image file.')
end

function EditorImagePixelationAndPreview.tooltipForStage(stage)
    stage = math.max(0, math.min(3, math.floor(tonumber(stage) or 0)))
    return '#Loc_Editor_PixelateTooltip' .. tostring(stage) .. '#'
end

function EditorImagePixelationAndPreview.updateButtonState(imageKey)
    local blocked = EditorImagePixelationAndPreview.isGifOrManagedAtlas(imageKey)
    local parsed = EditorImagePixelationAndPreview.parseKey(imageKey)
    SKIN:Bang('!SetVariable', 'EditorPixelateButtonTooltip', blocked and EditorImagePixelationAndPreview.gifUnsupportedMessage() or EditorImagePixelationAndPreview.tooltipForStage(parsed.stage))
    SKIN:Bang('!SetVariable', 'EditorPixelateButtonBgColor', blocked and '#EditorButtonDisabledBgColor#' or '#EditorButtonBgColor#')
    SKIN:Bang('!SetVariable', 'EditorPixelateButtonTextColor', blocked and '#EditorButtonDisabledTextColor#' or '#EditorButtonTextColor#')
    SKIN:Bang('!SetVariable', 'EditorPixelateButtonCommand', blocked and '' or '[!CommandMeasure MeasureInputCommit "ApplyImagePixelation()"]')
    SKIN:Bang('!SetVariable', 'EditorPixelateButtonCursor', blocked and '0' or '1')
    SKIN:Bang('!UpdateMeter', 'MeterViewerPixelButtonBackground')
    SKIN:Bang('!UpdateMeter', 'MeterViewerPixelButtonLabel')
end

function EditorImagePixelationAndPreview.syncState(imageKey)
    EditorImagePixelationAndPreview.updateButtonState(imageKey or SKIN:GetVariable('EditorImageKeyValue', ''))
end

EditorImagePixelationAndPreview.bridge().syncPixelationState = function(imageKey)
    return EditorImagePixelationAndPreview.syncState(imageKey)
end

function EditorImagePixelationAndPreview.luaPath()
    return EditorImagePixelationAndPreview.joinPath(EditorImagePixelationAndPreview.trim(SKIN:GetVariable('@', '')), 'Defaults\\Runtime\\luas\\ImagePixelation.lua')
end

function EditorImagePixelationAndPreview.helperPath()
    return EditorImagePixelationAndPreview.joinPath(EditorImagePixelationAndPreview.trim(SKIN:GetVariable('@', '')), 'Defaults\\Runtime\\helpers\\PixelateImage.ps1')
end

function EditorImagePixelationAndPreview.load()
    if EditorImagePixelationAndPreview.pixelator ~= nil then
        return EditorImagePixelationAndPreview.pixelator
    end
    if EditorImagePixelationAndPreview.loadFailed then
        return nil
    end

    if EditorImagePixelationAndPreview.module == nil then
        local ok, moduleOrError = pcall(dofile, EditorImagePixelationAndPreview.luaPath())
        if not ok or type(moduleOrError) ~= 'table' or type(moduleOrError.create) ~= 'function' then
            EditorImagePixelationAndPreview.loadFailed = true
            EditorImagePixelationAndPreview.bridge().log('Warning', 'Editor image pixelation module could not be loaded: ' .. tostring(moduleOrError))
            return nil
        end
        EditorImagePixelationAndPreview.module = moduleOrError
    end

    EditorImagePixelationAndPreview.pixelator = EditorImagePixelationAndPreview.module.create(SKIN, {
        helperPath = EditorImagePixelationAndPreview.helperPath(),
        argsVariable = 'EditorPixelateArgs',
        runMeasure = 'MeasureEditorPixelateRun',
        defaultWidth = 1,
        defaultHeight = 1,
        defaultBlockSize = 2,
        fitMode = 'Stretch',
        sampleMode = 'Average',
    })
    return EditorImagePixelationAndPreview.pixelator
end

function EditorImagePixelationAndPreview.cleanupToken()
    EditorImagePixelationAndPreview.cleanupSequence = EditorImagePixelationAndPreview.cleanupSequence + 1
    local seed = table.concat({
        tostring(os.time()),
        tostring(EditorImagePixelationAndPreview.cleanupSequence),
    }, '|')
    if EditorImagePixelationAndPreview.module and type(EditorImagePixelationAndPreview.module.hash) == 'function' then
        return EditorImagePixelationAndPreview.module.hash(seed)
    end
    return tostring(os.time()) .. tostring(EditorImagePixelationAndPreview.cleanupSequence)
end

function EditorImagePixelationAndPreview.buildCleanupPayload(token)
    local module = EditorImagePixelationAndPreview.module
    if not module or type(module.base64Encode) ~= 'function' or type(module.jsonString) ~= 'function' then
        return ''
    end
    local pairs = {
        { 'CleanupPixelSiblings', true },
        { 'ItemImageDirectory', EditorImagePixelationAndPreview.itemImageDirectory() },
        { 'Token', token },
    }
    local json = {}
    for _, pair in ipairs(pairs) do
        local key = pair[1]
        local value = pair[2]
        if type(value) == 'boolean' then
            json[#json + 1] = module.jsonString(key) .. ':' .. (value and 'true' or 'false')
        else
            json[#json + 1] = module.jsonString(key) .. ':' .. module.jsonString(value)
        end
    end
    return module.base64Encode('{' .. table.concat(json, ',') .. '}')
end

function EditorImagePixelationAndPreview.buildCleanupArgs(payload)
    local module = EditorImagePixelationAndPreview.module
    if not module or type(module.quotePowerShellArgument) ~= 'function' then
        return ''
    end
    local quote = module.quotePowerShellArgument
    return table.concat({
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', quote(EditorImagePixelationAndPreview.helperPath()),
        '-RequestJsonBase64', quote(payload),
    }, ' ')
end

function CleanupEditorPixelationImagesAfterPersist()
    if EditorImagePixelationAndPreview.cleanupPendingToken ~= '' then
        EditorImagePixelationAndPreview.logWarning('Editor image pixelation cleanup skipped because a previous cleanup request is still pending.')
        return false
    end
    if not EditorImagePixelationAndPreview.load() then
        return false
    end
    if not SKIN:GetMeasure('MeasureEditorPixelCleanupRun') then
        EditorImagePixelationAndPreview.logWarning('Editor image pixelation cleanup RunCommand measure is missing.')
        return false
    end

    local token = EditorImagePixelationAndPreview.cleanupToken()
    local payload = EditorImagePixelationAndPreview.buildCleanupPayload(token)
    local args = EditorImagePixelationAndPreview.buildCleanupArgs(payload)
    if payload == '' or args == '' then
        EditorImagePixelationAndPreview.logWarning('Editor image pixelation cleanup request could not be built.')
        return false
    end

    EditorImagePixelationAndPreview.cleanupPendingToken = token
    SKIN:Bang('!SetVariable', 'EditorPixelCleanupArgs', args)
    SKIN:Bang('!UpdateMeasure', 'MeasureEditorPixelCleanupRun')
    SKIN:Bang('!CommandMeasure', 'MeasureEditorPixelCleanupRun', 'Run')
    EditorImagePixelationAndPreview.logDebug('Editor image pixelation cleanup started. token=' .. tostring(token))
    return true
end

function EditorImagePixelationAndPreview.itemImageDirectory()
    return EditorImagePixelationAndPreview.trim(EditorImagePixelationAndPreview.bridge().itemImageDirectory())
end

function EditorImagePixelationAndPreview.itemImagePath(imageKey)
    return EditorImagePixelationAndPreview.bridge().itemImagePath(EditorImagePixelationAndPreview.fileName(imageKey))
end

function EditorImagePixelationAndPreview.setLoading(stage, visible)
    if visible then
        SKIN:Bang('!SetVariable', 'EditorLoadingTextLine1', '#Loc_Editor_PixelateLoading' .. tostring(stage) .. '_Line1#')
        SKIN:Bang('!SetVariable', 'EditorLoadingTextLine2', '#Loc_Editor_PixelateLoading_Line2#')
        ApplyEditorStaticLocalizationTextFits()
        EditorImagePixelationAndPreview.bridge().setLoadingVisible(true)
        return
    end

    SKIN:Bang('!SetVariable', 'EditorLoadingTextLine1', '#Loc_Editor_Loading_Line1#')
    SKIN:Bang('!SetVariable', 'EditorLoadingTextLine2', '#Loc_Editor_Loading_Line2#')
    ApplyEditorStaticLocalizationTextFits()
    EditorImagePixelationAndPreview.bridge().setLoadingVisible(false)
end

function EditorImagePixelationAndPreview.start(currentImageKey, parsed, nextStage)
    if EditorImagePixelationAndPreview.isGifOrManagedAtlas(currentImageKey) then
        return false, EditorImagePixelationAndPreview.gifUnsupportedMessage(), true
    end
    local pixelator = EditorImagePixelationAndPreview.load()
    if not pixelator then
        return false, 'Image pixelation could not be started.'
    end

    local sourceImageKey = EditorImagePixelationAndPreview.findOriginalKey(parsed, currentImageKey)
    local itemImageDirectory = EditorImagePixelationAndPreview.itemImageDirectory()
    local outputKey = parsed.baseStem .. '_p' .. tostring(nextStage) .. '.png'
    local blockSize = EditorImagePixelationAndPreview.strengths[nextStage] or EditorImagePixelationAndPreview.strengths[1]
    local sourcePath = EditorImagePixelationAndPreview.itemImagePath(sourceImageKey)
    if EditorImagePixelationAndPreview.isGifOrManagedAtlas(sourceImageKey)
        or EditorImagePixelationAndPreview.isGifOrManagedAtlas(sourcePath) then
        return false, EditorImagePixelationAndPreview.gifUnsupportedMessage(), true
    end
    local outputPath = EditorImagePixelationAndPreview.joinPath(itemImageDirectory, outputKey)
    local signature = table.concat({
        EditorImagePixelationAndPreview.trim(sourcePath),
        EditorImagePixelationAndPreview.fileName(currentImageKey),
        sourceImageKey,
        outputKey,
        tostring(nextStage),
        tostring(blockSize),
    }, '|')

    EditorImagePixelationAndPreview.pending = {
        outputKey = outputKey,
        stage = nextStage,
        sourceKey = sourceImageKey,
        sourcePath = sourcePath,
        outputPath = outputPath,
    }
    EditorImagePixelationAndPreview.logDebug(table.concat({
        'Editor image pixelation request starting.',
        'stage=' .. tostring(nextStage),
        'sourceKey=' .. tostring(sourceImageKey),
        'outputKey=' .. tostring(outputKey),
        'sourcePath=' .. tostring(sourcePath),
        'outputPath=' .. tostring(outputPath),
    }, ' '))

    local result = pixelator:requestImage({
        sourcePath = sourcePath,
        outputPath = outputPath,
        width = 1,
        height = 1,
        blockSize = blockSize,
        fitMode = 'Stretch',
        sampleMode = 'Average',
        preserveSourceSize = true,
        itemImageDirectory = itemImageDirectory,
        signature = signature,
    })

    if result and result.ready then
        EditorImagePixelationAndPreview.pending = nil
        EditorImagePixelationAndPreview.bridge().commitImageKey(outputKey)
        EditorImagePixelationAndPreview.syncState(outputKey)
        return true, ''
    end
    if result and result.failed then
        EditorImagePixelationAndPreview.pending = nil
        return false, EditorImagePixelationAndPreview.trim(result.message) ~= '' and result.message or 'Image pixelation failed.'
    end

    EditorImagePixelationAndPreview.setLoading(nextStage, true)
    return true, ''
end

function ApplyImagePixelation()
    EditorImagePixelationAndPreview.bridge().playClick()

    if EditorImagePixelationAndPreview.pending ~= nil then
        return false
    end
    if not EditorImagePixelationAndPreview.bridge().hasSelection() then
        EditorImagePixelationAndPreview.bridge().log('Warning', 'No draft item is selected for image pixelation.')
        return false
    end

    local rawImageKey = SKIN:GetVariable('EditorImageKeyValue', '')
    if EditorImagePixelationAndPreview.isGifOrManagedAtlas(rawImageKey) then
        return EditorImagePixelationAndPreview.showGifUnsupported()
    end
    local currentImageKey = EditorImagePixelationAndPreview.bridge().normalizeImageAsset(rawImageKey)
    if currentImageKey == '' then
        currentImageKey = EditorImagePixelationAndPreview.bridge().defaultImageKey
    end
    local parsed = EditorImagePixelationAndPreview.parseKey(currentImageKey)

    if parsed.stage >= 3 then
        local originalKey = EditorImagePixelationAndPreview.findOriginalKey(parsed, currentImageKey)
        if originalKey ~= '' and originalKey ~= EditorImagePixelationAndPreview.fileName(currentImageKey) then
            EditorImagePixelationAndPreview.bridge().commitImageKey(originalKey)
            EditorImagePixelationAndPreview.syncState(originalKey)
            return true
        end
        EditorImagePixelationAndPreview.syncState(currentImageKey)
        local message = EditorImagePixelationAndPreview.missingOriginalMessage(parsed, currentImageKey)
        EditorImagePixelationAndPreview.logWarning('Editor image pixelation original source was not found; keeping current p3 image. ' .. message)
        EditorImagePixelationAndPreview.userAlert(message)
        return false
    end

    local nextStage = parsed.stage + 1
    local ok, message, unsupported = EditorImagePixelationAndPreview.start(currentImageKey, parsed, nextStage)
    if not ok then
        if unsupported then
            return EditorImagePixelationAndPreview.showGifUnsupported()
        end
        EditorImagePixelationAndPreview.logWarning('Editor image pixelation could not start. ' .. tostring(message))
        EditorImagePixelationAndPreview.userAlert(message)
        EditorImagePixelationAndPreview.setLoading(nextStage, false)
        return false
    end
    return true
end

function HandleEditorPixelationComplete()
    local pending = EditorImagePixelationAndPreview.pending
    EditorImagePixelationAndPreview.pending = nil
    EditorImagePixelationAndPreview.setLoading(pending and pending.stage or 0, false)

    local pixelator = EditorImagePixelationAndPreview.load()
    if not pixelator then
        return false
    end

    local output = ''
    local measure = SKIN:GetMeasure('MeasureEditorPixelateRun')
    if measure then
        output = measure:GetStringValue()
    end

    if EditorImagePixelationAndPreview.runCommandErrorCode(measure) == 103 then
        EditorImagePixelationAndPreview.clearPixelatorPending(pixelator)
        EditorImagePixelationAndPreview.alertPowerShellUnavailable('Editor image pixelation')
        EditorImagePixelationAndPreview.syncState(SKIN:GetVariable('EditorImageKeyValue', ''))
        return false
    end

    EditorImagePixelationAndPreview.logDebug(table.concat({
        'Editor image pixelation completion received.',
        'hadPending=' .. tostring(pending ~= nil),
        'pixelatorPendingToken=' .. tostring(pixelator.pendingToken or ''),
        'outputChars=' .. tostring(#tostring(output or '')),
        'outputPreview=' .. EditorImagePixelationAndPreview.outputPreview(output),
    }, ' '))

    if pending == nil and EditorImagePixelationAndPreview.trim(pixelator.pendingToken) == '' then
        EditorImagePixelationAndPreview.logWarning('Editor image pixelation completion ignored because there is no pending request. outputPreview=' .. EditorImagePixelationAndPreview.outputPreview(output))
        return false
    end

    local result = pixelator:handleComplete(output)
    if EditorImagePixelationAndPreview.trim(result.errorCode):upper() == 'GIF_PIXELATION_UNSUPPORTED'
        or (pending and (EditorImagePixelationAndPreview.isGifOrManagedAtlas(pending.sourceKey)
            or EditorImagePixelationAndPreview.isGifOrManagedAtlas(pending.sourcePath))) then
        EditorImagePixelationAndPreview.syncState(SKIN:GetVariable('EditorImageKeyValue', ''))
        return EditorImagePixelationAndPreview.showGifUnsupported()
    end

    if not result.accepted then
        local userMessage = EditorImagePixelationAndPreview.trim(result.userMessage) ~= '' and result.userMessage or result.message
        EditorImagePixelationAndPreview.logWarning('Editor image pixelation completion rejected. ' .. tostring(result.message or ''))
        EditorImagePixelationAndPreview.userAlert(userMessage)
        return false
    end

    if result.itemImageAssets and EditorImagePixelationAndPreview.trim(result.itemImageAssets) ~= '' then
        SKIN:Bang('!SetVariable', 'ItemImageAssets', result.itemImageAssets)
    end
    if result.itemImageAtlasProfilesPresent then
        SKIN:Bang('!SetVariable', 'ItemImageAtlasProfiles', result.itemImageAtlasProfiles or '')
        SKIN:Bang('!SetVariableGroup', 'ItemImageAtlasProfiles', result.itemImageAtlasProfiles or '', 'DMeloper')
    end

    local resolvedOutputKey = pending and pending.outputKey or EditorImagePixelationAndPreview.fileName(result.outputPath)
    if result.ok and resolvedOutputKey ~= '' then
        EditorImagePixelationAndPreview.bridge().commitImageKey(resolvedOutputKey)
        EditorImagePixelationAndPreview.syncState(resolvedOutputKey)
        return true
    end

    local message = EditorImagePixelationAndPreview.trim(result.userMessage) ~= '' and result.userMessage or result.message
    if EditorImagePixelationAndPreview.trim(message) == '' then
        message = 'Image pixelation failed.'
    end
    EditorImagePixelationAndPreview.logWarning('Editor image pixelation failed. ' .. tostring(message))
    EditorImagePixelationAndPreview.userAlert(message)
    EditorImagePixelationAndPreview.syncState(SKIN:GetVariable('EditorImageKeyValue', ''))
    return false
end

function HandleEditorPixelCleanupComplete()
    local expectedToken = EditorImagePixelationAndPreview.cleanupPendingToken
    EditorImagePixelationAndPreview.cleanupPendingToken = ''
    local output = ''
    local measure = SKIN:GetMeasure('MeasureEditorPixelCleanupRun')
    if measure then
        output = measure:GetStringValue()
    end

    local module = EditorImagePixelationAndPreview.module
    if not module or type(module.parsePairs) ~= 'function' then
        EditorImagePixelationAndPreview.logWarning('Editor image pixelation cleanup completion ignored because the module is not loaded.')
        return false
    end

    local values = module.parsePairs(output)
    local token = EditorImagePixelationAndPreview.trim(values.DMEL_TOKEN)
    local status = EditorImagePixelationAndPreview.trim(values.DMEL_STATUS):upper()
    local message = EditorImagePixelationAndPreview.trim(values.DMEL_MESSAGE)
    local deleted = EditorImagePixelationAndPreview.trim(values.DMEL_DELETED)
    local errorDetail = EditorImagePixelationAndPreview.trim(values.DMEL_ERROR_DETAIL)
    local itemImageAssets = EditorImagePixelationAndPreview.trim(values.DMEL_ITEMIMAGEASSETS)
    local itemImageAtlasProfiles = EditorImagePixelationAndPreview.trim(values.DMEL_ITEMIMAGEATLASPROFILES)
    local itemImageAtlasProfilesPresent = values.DMEL_ITEMIMAGEATLASPROFILES ~= nil
    if expectedToken == '' or token == '' or token ~= expectedToken then
        EditorImagePixelationAndPreview.logWarning(table.concat({
            'Editor image pixelation cleanup completion rejected.',
            'expected=' .. (expectedToken ~= '' and expectedToken or '<empty>'),
            'received=' .. (token ~= '' and token or '<empty>'),
            'status=' .. (status ~= '' and status or '<empty>'),
            'message=' .. (message ~= '' and message or '<empty>'),
            'outputPreview=' .. EditorImagePixelationAndPreview.outputPreview(output),
        }, ' '))
        return false
    end

    if itemImageAssets ~= '' then
        SKIN:Bang('!SetVariable', 'ItemImageAssets', itemImageAssets)
    end
    if itemImageAtlasProfilesPresent then
        SKIN:Bang('!SetVariable', 'ItemImageAtlasProfiles', itemImageAtlasProfiles)
        SKIN:Bang('!SetVariableGroup', 'ItemImageAtlasProfiles', itemImageAtlasProfiles, 'DMeloper')
    end
    if status == 'OK' then
        EditorImagePixelationAndPreview.logDebug('Editor image pixelation cleanup completed. deleted=' .. (deleted ~= '' and deleted or '<none>'))
        return true
    end
    if status == 'WARN' then
        EditorImagePixelationAndPreview.logWarning('Editor image pixelation cleanup completed with warnings. deleted=' .. (deleted ~= '' and deleted or '<none>') .. ' detail=' .. errorDetail)
        return true
    end

    EditorImagePixelationAndPreview.logWarning('Editor image pixelation cleanup failed. status=' .. status .. ' message=' .. message .. ' detail=' .. errorDetail)
    return false
end
