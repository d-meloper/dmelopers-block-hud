return function(app)
    local methods = app.methods
    local trim = app.trim
    local helperResult = app.helperResult
    -- Startup auto-run helpers must keep the DMEL_VALUE result contract.
    local function normalizeStartupAutoRunOutput(raw)
        return helperResult.normalizeStartupAutoRunOutput(raw)
    end

    local function parseStartupAutoRunResult(raw, fallback)
        return helperResult.parseStartupAutoRunResult(raw, fallback, methods.normalizeToggleValue)
    end

    local function defaultLoadingMessage()
        return methods.localize('Settings_Loading', 'Loading...\\nPlease wait.')
    end

    local function showModalAlert(level, summaryKey, fallback, logPath)
        if not methods.ShowModalAlertByKeys then
            return false
        end
        return methods.ShowModalAlertByKeys(level, summaryKey, fallback, logPath)
    end

    app.cacheHelpers = {
        normalizeStartupAutoRunOutput = normalizeStartupAutoRunOutput,
        parseStartupAutoRunResult = parseStartupAutoRunResult,
        defaultLoadingMessage = defaultLoadingMessage,
        showModalAlert = showModalAlert,
    }
end
