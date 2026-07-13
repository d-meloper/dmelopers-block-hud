EditorInputCommitPixelBridge = {
    trim = trim,
    normalizeImageAsset = normalizeImageAsset,
    defaultImageKey = DEFAULT_NEW_ITEM_IMAGE,
    playClick = playUiClick,
    hasSelection = hasActiveEditorSelection,
    log = logMessage,
    alert = logEditorErrorAndAlert,
    localize = function(key, fallback)
        return L(key, fallback)
    end,
    userAlert = function(message)
        local summary = trim(message)
        if summary == '' then
            summary = 'Image pixelation failed.'
        end
        return showEditorModalAlert('error', '', summary)
    end,
    setLoadingVisible = setEditorLoadingVisible,
    commitImageKey = function(imageKey)
        return commitImageKeyForLocator(imageKey, nil)
    end,
    itemImageDirectory = function()
        local paths = ensureService().GetPaths(editorRoot)
        return trim(paths and paths.ItemImageDirectory or '')
    end,
    itemImagePath = function(imageKey)
        return ensureService().GetImagePath(editorRoot, normalizeImageAsset(imageKey))
    end,
}

function SyncEditorPixelationState(imageKey)
    if EditorInputCommitPixelBridge and type(EditorInputCommitPixelBridge.syncPixelationState) == 'function' then
        return EditorInputCommitPixelBridge.syncPixelationState(imageKey)
    end
    return nil
end

function ApplyImagePixelation()
    logMessage('Warning', 'Editor image pixelation module is not loaded.')
    return false
end

function HandleEditorPixelationComplete()
    logMessage('Warning', 'Editor image pixelation completion was ignored because the module is not loaded.')
    return false
end

function CleanupEditorPixelationImagesAfterPersist()
    return false
end

function HandleEditorPixelCleanupComplete()
    logMessage('Warning', 'Editor image pixelation cleanup completion was ignored because the module is not loaded.')
    return false
end
