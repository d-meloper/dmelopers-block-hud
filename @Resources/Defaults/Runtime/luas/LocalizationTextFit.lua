local TextFit = {}

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

local function maxUnitsFromWidth(widthPx, baseFontSize, unitPixelFactor)
    local width = tonumber(widthPx) or 0
    local fontSize = tonumber(baseFontSize) or 0
    if width <= 0 or fontSize <= 0 then
        return 0
    end
    local factor = tonumber(unitPixelFactor) or 0.72
    if factor <= 0 then
        factor = 0.72
    end
    return width / math.max(1, fontSize * factor)
end

local function roundFontSize(value)
    return math.floor(((tonumber(value) or 0) * 10) + 0.5) / 10
end

local function clampMinimumFontSize(baseFontSize, minScale, minFontSize)
    local base = tonumber(baseFontSize) or 10
    local scale = numberValue(minScale, 0.70)
    if scale <= 0 or scale > 1 then
        scale = 0.70
    end

    local minimum = base * scale
    local explicitMinimum = numberValue(minFontSize, 0)
    if explicitMinimum > 0 and minimum < explicitMinimum then
        minimum = explicitMinimum
    end
    if minimum > base then
        minimum = base
    end
    return minimum
end

local function measureTextWidth(skin, probeMeterName, text, fontSize)
    local probe = trim(probeMeterName)
    if not skin or not skin.Bang or not skin.GetMeter or probe == '' then
        return nil
    end

    skin:Bang('!SetOption', probe, 'Text', tostring(text or ''))
    skin:Bang('!SetOption', probe, 'FontSize', tostring(fontSize or 10))
    skin:Bang('!UpdateMeter', probe)

    local ok, meter = pcall(function()
        return skin:GetMeter(probe)
    end)
    if not ok or not meter or not meter.GetW then
        return nil
    end

    local widthOk, width = pcall(function()
        return meter:GetW()
    end)
    width = tonumber(widthOk and width or nil)
    if width == nil or width < 0 then
        return nil
    end
    return width
end

local function measuredFitFontSize(skin, text, profile, baseFontSize)
    local width = tonumber(profile.widthPx) or 0
    if width <= 0 then
        return nil
    end

    local probe = trim(profile.probeMeterName)
    if probe == '' then
        return nil
    end

    local minimum = clampMinimumFontSize(baseFontSize, profile.minScale, profile.minFontSize)
    local base = tonumber(baseFontSize) or 10
    local resolvedText = resolveText(skin, text)
    if trim(resolvedText) == '' then
        return base
    end

    local baseWidth = measureTextWidth(skin, probe, resolvedText, base)
    if baseWidth == nil then
        return nil
    end
    if baseWidth <= width then
        return roundFontSize(base)
    end

    local minWidth = measureTextWidth(skin, probe, resolvedText, minimum)
    if minWidth == nil then
        return nil
    end
    if minWidth > width then
        return roundFontSize(minimum)
    end

    local low = minimum
    local high = base
    local best = minimum
    for _ = 1, 8 do
        local mid = (low + high) / 2
        local measured = measureTextWidth(skin, probe, resolvedText, mid)
        if measured == nil then
            return nil
        end
        if measured <= width then
            best = mid
            low = mid
        else
            high = mid
        end
    end

    return roundFontSize(best)
end

function TextFit.ComputeScale(skin, locKey, localizedText, profile)
    profile = profile or {}
    local baseFontSize = numberValue(profile.baseFontSize, 10)
    local minScale = numberValue(profile.minScale, 0.70)
    if minScale <= 0 or minScale > 1 then
        minScale = 0.70
    end

    local text = resolveText(skin, localizedText)
    local textUnits = TextFit.EstimateTextUnits(text)
    if textUnits <= 0 then
        return 1.0
    end

    local widthUnits = maxUnitsFromWidth(profile.widthPx, baseFontSize, profile.unitPixelFactor)
    if widthUnits <= 0 then
        return 1.0
    end
    if textUnits <= widthUnits then
        return 1.0
    end

    local scale = widthUnits / textUnits
    if scale > 1 then
        return 1.0
    end
    if scale < minScale then
        return minScale
    end
    return scale
end

function TextFit.FitFontSize(skin, locKey, localizedText, profile)
    profile = profile or {}
    local baseFontSize = numberValue(profile.baseFontSize, 10)
    local measuredSize = measuredFitFontSize(skin, localizedText, profile, baseFontSize)
    if measuredSize ~= nil then
        return measuredSize
    end

    local scale = TextFit.ComputeScale(skin, locKey, localizedText, profile)
    local value = baseFontSize * scale
    local minimum = clampMinimumFontSize(baseFontSize, profile.minScale, profile.minFontSize)
    if value < minimum then
        value = minimum
    end
    return roundFontSize(value)
end

function TextFit.ApplyMeterTextFit(skin, meterName, text, profile)
    if not skin or not skin.Bang then
        return nil
    end
    profile = profile or {}
    local fontSize = TextFit.FitFontSize(skin, profile.locKey, text, profile)
    skin:Bang('!SetOption', meterName, 'FontSize', tostring(fontSize))
    if profile.setText ~= false then
        skin:Bang('!SetOption', meterName, 'Text', tostring(text or ''))
    end
    if profile.update ~= false then
        skin:Bang('!UpdateMeter', meterName)
    end
    return fontSize
end

return TextFit
