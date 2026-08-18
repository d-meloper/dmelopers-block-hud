local TextFit = {}

local DEFAULTS = {
    readableScale = 0.75,
    readableMinFontSize = 8,
    emergencyScale = 0.60,
    emergencyMinFontSize = 6,
    compactScale = 0.30,
    compactMinFontSize = 3,
    maxLines = 2,
    extendedMaxLines = 4,
    unitPixelFactor = 0.72,
    searchIterations = 8,
}

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function numberValue(value, fallback)
    local numeric = tonumber(trim(value))
    if numeric == nil then
        return fallback
    end
    return numeric
end

local function positiveNumber(value, fallback)
    local numeric = numberValue(value, fallback)
    if numeric == nil or numeric <= 0 then
        return fallback
    end
    return numeric
end

local function roundFontSize(value)
    return math.floor(((tonumber(value) or 0) * 10) + 0.5) / 10
end

local function resolveText(skin, text)
    local value = tostring(text or '')
    if skin and skin.ReplaceVariables then
        local ok, replaced = pcall(function()
            return skin:ReplaceVariables(value)
        end)
        if ok and replaced ~= nil then
            value = replaced
        end
    end
    return value
end

local function nextCodepoint(text, index)
    local b1 = text:byte(index) or 0
    if b1 < 128 then
        return b1, index + 1
    end
    local b2 = text:byte(index + 1) or 0
    if b1 >= 194 and b1 <= 223 then
        return ((b1 - 192) * 64) + (b2 - 128), index + 2
    end
    local b3 = text:byte(index + 2) or 0
    if b1 >= 224 and b1 <= 239 then
        return ((b1 - 224) * 4096) + ((b2 - 128) * 64) + (b3 - 128), index + 3
    end
    local b4 = text:byte(index + 3) or 0
    if b1 >= 240 and b1 <= 244 then
        return ((b1 - 240) * 262144) + ((b2 - 128) * 4096) + ((b3 - 128) * 64) + (b4 - 128), index + 4
    end
    return b1, index + 1
end

local function codepointUnits(cp)
    if cp == 9 then
        return 2.0
    end
    if cp == 10 or cp == 13 then
        return 0.0
    end
    if cp == 32 then
        return 0.45
    end
    if cp < 128 then
        local ch = string.char(cp)
        if ch:match('[ilI1%.,:;!|]') then
            return 0.38
        end
        if ch:match('[fjrt%-%s]') then
            return 0.55
        end
        if ch:match('[mwMW@#%%&]') then
            return 1.2
        end
        return 1.0
    end
    if (cp >= 4352 and cp <= 4607)
        or (cp >= 11904 and cp <= 42191)
        or (cp >= 44032 and cp <= 55215)
        or (cp >= 63744 and cp <= 64255)
        or (cp >= 65040 and cp <= 65135)
        or (cp >= 65280 and cp <= 65519) then
        return 2.0
    end
    return 1.05
end

function TextFit.EstimateTextUnits(text)
    local total = 0.0
    local value = tostring(text or ''):gsub('\\r\\n', '\n'):gsub('\\n', '\n'):gsub('\\r', '\n')
    local index = 1
    while index <= #value do
        local cp, nextIndex = nextCodepoint(value, index)
        total = total + codepointUnits(cp)
        index = nextIndex
    end
    return total
end

local function mergeDefaults(overrides)
    local result = {}
    for key, value in pairs(DEFAULTS) do
        result[key] = value
    end
    for key, value in pairs(overrides or {}) do
        result[key] = value
    end
    return result
end

local function minimumFontSize(baseFontSize, scale, explicitMinimum)
    local base = positiveNumber(baseFontSize, 10)
    local resolvedScale = numberValue(scale, 1)
    if resolvedScale <= 0 or resolvedScale > 1 then
        resolvedScale = 1
    end
    local minimum = math.max(base * resolvedScale, positiveNumber(explicitMinimum, 0))
    return roundFontSize(math.min(base, minimum))
end

local function meterDimensions(skin, meterName)
    if not skin or not skin.GetMeter or trim(meterName) == '' then
        return nil, nil
    end
    local ok, meter = pcall(function()
        return skin:GetMeter(meterName)
    end)
    if not ok or not meter then
        return nil, nil
    end
    local width = nil
    local height = nil
    if meter.GetW then
        local widthOk, value = pcall(function()
            return meter:GetW()
        end)
        if widthOk then
            width = tonumber(value)
        end
    end
    if meter.GetH then
        local heightOk, value = pcall(function()
            return meter:GetH()
        end)
        if heightOk then
            height = tonumber(value)
        end
    end
    return width, height
end

local function setProbeOption(skin, setter, probe, optionName, value)
    if setter then
        setter(probe, optionName, value)
        return
    end
    skin:Bang('!SetOption', probe, optionName, tostring(value or ''))
end

local function measureSingleLine(skin, probeMeterName, text, fontSize, optionSetter)
    local probe = trim(probeMeterName)
    if not skin or not skin.Bang or probe == '' then
        return nil
    end
    setProbeOption(skin, optionSetter, probe, 'Text', tostring(text or ''))
    setProbeOption(skin, optionSetter, probe, 'FontSize', tostring(fontSize))
    setProbeOption(skin, optionSetter, probe, 'ClipString', '0')
    skin:Bang('!UpdateMeter', probe)
    local width, height = meterDimensions(skin, probe)
    if width == nil or width < 0 then
        return nil
    end
    return { width = width, height = height }
end

local function measureWrapped(skin, probeMeterName, text, fontSize, widthPx, optionSetter)
    local probe = trim(probeMeterName)
    if not skin or not skin.Bang or probe == '' or widthPx <= 0 then
        return nil
    end
    setProbeOption(skin, optionSetter, probe, 'Text', tostring(text or ''))
    setProbeOption(skin, optionSetter, probe, 'FontSize', tostring(fontSize))
    setProbeOption(skin, optionSetter, probe, 'ClipString', '2')
    setProbeOption(skin, optionSetter, probe, 'ClipStringW', tostring(widthPx))
    skin:Bang('!ShowMeter', probe)
    skin:Bang('!UpdateMeter', probe)
    local width, height = meterDimensions(skin, probe)
    skin:Bang('!HideMeter', probe)
    if height == nil or height < 0 then
        return nil
    end
    return { width = width, height = height }
end

local function estimateSingleLine(text, fontSize, unitPixelFactor)
    local factor = positiveNumber(unitPixelFactor, DEFAULTS.unitPixelFactor)
    return {
        width = TextFit.EstimateTextUnits(text) * fontSize * factor,
        height = fontSize * 1.25,
        estimated = true,
    }
end

local function estimatedWrapped(single, widthPx)
    local lines = math.max(1, math.ceil(single.width / math.max(1, widthPx)))
    return {
        width = math.min(single.width, widthPx),
        height = single.height * lines,
        lines = lines,
        estimated = true,
    }
end

local function result(mode, fontSize, fits, truncated, measuredWidth, measuredHeight)
    return {
        fontSize = roundFontSize(fontSize),
        mode = mode,
        fits = fits == true,
        truncated = truncated == true,
        measuredWidth = tonumber(measuredWidth),
        measuredHeight = tonumber(measuredHeight),
    }
end

function TextFit.Create(skin, defaults)
    local options = mergeDefaults(defaults)
    local fitter = {}

    local function singleMeasurement(text, fontSize, optionSetter)
        return measureSingleLine(skin, options.widthProbeMeterName, text, fontSize, optionSetter)
            or estimateSingleLine(text, fontSize, options.unitPixelFactor)
    end

    local function wrapMeasurement(text, fontSize, widthPx, single, optionSetter)
        local measured = measureWrapped(skin, options.wrapProbeMeterName, text, fontSize, widthPx, optionSetter)
        if measured then
            return measured
        end
        return estimatedWrapped(single or singleMeasurement(text, fontSize, optionSetter), widthPx)
    end

    local function largestFit(minimum, maximum, check)
        local maxResult = check(maximum)
        if maxResult.fits then
            return maximum, maxResult
        end
        local minResult = check(minimum)
        if not minResult.fits then
            return minimum, minResult
        end
        local low = minimum
        local high = maximum
        local best = minimum
        local bestResult = minResult
        local iterations = math.max(1, math.floor(positiveNumber(options.searchIterations, 8)))
        for _ = 1, iterations do
            local middle = (low + high) / 2
            local candidate = check(middle)
            if candidate.fits then
                best = middle
                bestResult = candidate
                low = middle
            else
                high = middle
            end
        end
        local rounded = roundFontSize(best)
        local roundedResult = check(rounded)
        if roundedResult.fits then
            return rounded, roundedResult
        end
        return roundFontSize(math.max(minimum, best - 0.1)), bestResult
    end

    function fitter:Apply(target)
        target = target or {}
        local meterName = trim(target.meterName)
        local text = resolveText(skin, target.text)
        local base = positiveNumber(target.baseFontSize, 10)
        local width = numberValue(target.widthPx, 0)
        local height = numberValue(target.heightPx, 0)
        local policy = trim(target.policy):lower()
        if policy ~= 'wrap2' and policy ~= 'wrap4' then
            policy = 'single-line'
        end

        local readableMinimum = minimumFontSize(base, options.readableScale, options.readableMinFontSize)
        local emergencyMinimum = minimumFontSize(base, options.emergencyScale, options.emergencyMinFontSize)
        local compactMinimum = minimumFontSize(base, options.compactScale, options.compactMinFontSize)
        if emergencyMinimum > readableMinimum then
            emergencyMinimum = readableMinimum
        end
        if compactMinimum > emergencyMinimum then
            compactMinimum = emergencyMinimum
        end

        -- Probe values only live for this synchronous Apply call. This avoids
        -- stale font/geometry assumptions across Rainmeter refreshes while
        -- eliminating repeated measurements and identical !SetOption bangs.
        local probeOptions = {}
        local singleMeasurements = {}
        local wrapMeasurements = {}
        local wrapChecks = {}
        local function measurementKey(fontSize)
            return tostring(fontSize)
        end
        local function applyProbeOption(probe, optionName, value)
            local resolved = tostring(value or '')
            local key = probe .. '\0' .. optionName
            if probeOptions[key] == resolved then
                return
            end
            skin:Bang('!SetOption', probe, optionName, resolved)
            probeOptions[key] = resolved
        end
        local function measuredSingle(fontSize)
            local key = measurementKey(fontSize)
            if not singleMeasurements[key] then
                singleMeasurements[key] = singleMeasurement(text, fontSize, applyProbeOption)
            end
            return singleMeasurements[key]
        end
        local function measuredWrap(fontSize)
            local key = measurementKey(fontSize)
            if not wrapMeasurements[key] then
                local single = measuredSingle(fontSize)
                wrapMeasurements[key] = wrapMeasurement(text, fontSize, width, single, applyProbeOption)
            end
            return wrapMeasurements[key]
        end

        local maxLines = math.max(1, math.floor(positiveNumber(options.maxLines, 2)))
        local extendedMaxLines = math.max(maxLines, math.floor(positiveNumber(options.extendedMaxLines, 4)))
        local function checkWrap(fontSize, lineLimit)
            local key = tostring(lineLimit) .. '\0' .. measurementKey(fontSize)
            if wrapChecks[key] then
                return wrapChecks[key]
            end
            local single = measuredSingle(fontSize)
            local measured = measuredWrap(fontSize)
            local lineHeight = positiveNumber(single.height, fontSize * 1.25)
            local allowedHeight = lineHeight * lineLimit + 1
            if height > 0 then
                allowedHeight = math.min(allowedHeight, height)
            end
            local checked = {
                fits = measured.height <= allowedHeight,
                width = measured.width,
                height = measured.height,
                allowedHeight = allowedHeight,
            }
            wrapChecks[key] = checked
            return checked
        end

        local chosen = nil
        local targetHeight = height
        local function checkSingle(fontSize)
            local measured = measuredSingle(fontSize)
            return {
                fits = width > 0 and measured.width <= width,
                width = measured.width,
                height = measured.height,
            }
        end

        if trim(text) == '' then
            chosen = result('single', base, true, false, 0, 0)
        elseif width <= 0 then
            chosen = result(policy == 'wrap4' and 'wrap4' or (policy == 'wrap2' and 'wrap2' or 'single'), base, false, true, nil, nil)
        else
            local singleSize, singleResult = largestFit(readableMinimum, base, checkSingle)
            if singleResult.fits then
                chosen = result('single', singleSize, true, false, singleResult.width, singleResult.height)
            elseif policy == 'single-line' then
                chosen = result('single', readableMinimum, false, true, singleResult.width, singleResult.height)
            else
                local function checkWrap2(fontSize)
                    return checkWrap(fontSize, maxLines)
                end

                local wrapSize, wrapResult = largestFit(readableMinimum, base, checkWrap2)
                if wrapResult.fits then
                    chosen = result('wrap2', wrapSize, true, false, wrapResult.width, wrapResult.height)
                else
                    local emergencySize, emergencyResult = largestFit(emergencyMinimum, readableMinimum, checkWrap2)
                    if emergencyResult.fits then
                        chosen = result('wrap2', emergencySize, true, false, emergencyResult.width, emergencyResult.height)
                    elseif policy == 'wrap4' then
                        local function checkWrap4(fontSize)
                            return checkWrap(fontSize, extendedMaxLines)
                        end
                        local compactSize, compactResult = largestFit(compactMinimum, base, checkWrap4)
                        if compactResult.fits then
                            chosen = result('wrap4', compactSize, true, false, compactResult.width, compactResult.height)
                        else
                            chosen = result('wrap4', compactMinimum, false, true, compactResult.width, compactResult.height)
                        end
                    else
                        chosen = result('wrap2', emergencyMinimum, false, true, emergencyResult.width, emergencyResult.height)
                    end
                end
            end
        end

        if skin and skin.Bang and meterName ~= '' then
            skin:Bang('!SetOption', meterName, 'FontSize', tostring(chosen.fontSize))
            skin:Bang('!SetOption', meterName, 'ClipString', '1')
            if targetHeight > 0 then
                local appliedHeight = targetHeight
                if chosen.mode == 'wrap2' or chosen.mode == 'wrap4' then
                    local single = measuredSingle(chosen.fontSize)
                    local lineHeight = positiveNumber(single.height, chosen.fontSize * 1.25)
                    local appliedMaxLines = chosen.mode == 'wrap4' and extendedMaxLines or maxLines
                    appliedHeight = math.min(targetHeight, math.ceil((lineHeight * appliedMaxLines) + 1))
                end
                skin:Bang('!SetOption', meterName, 'H', tostring(appliedHeight))
            end
        end
        return chosen
    end

    return fitter
end

return TextFit
