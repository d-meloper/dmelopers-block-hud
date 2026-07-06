local LanguageBranching = {}

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

function LanguageBranching.NormalizeLanguageCode(raw, fallback)
    local resolved = trim(raw)
    if resolved == '' then
        resolved = trim(fallback)
    end

    local lowered = string.lower(resolved)
    if lowered == 'ko' or lowered == 'ko-kr' then
        return 'ko-KR'
    end
    if lowered == 'en' or lowered == 'en-us' then
        return 'en-US'
    end
    return resolved
end

function LanguageBranching.IsKorean(raw)
    return LanguageBranching.NormalizeLanguageCode(raw, '') == 'ko-KR'
end

function LanguageBranching.SelectKoreanElseGlobal(raw, koreanValue, globalValue)
    if LanguageBranching.IsKorean(raw) then
        return koreanValue
    end
    return globalValue
end

function LanguageBranching.CurrentSkinLanguageCode(skin, fallback)
    local resolvedFallback = fallback or 'ko-KR'
    if skin and skin.GetVariable then
        return LanguageBranching.NormalizeLanguageCode(skin:GetVariable('LanguageCode', resolvedFallback), resolvedFallback)
    end
    return LanguageBranching.NormalizeLanguageCode('', resolvedFallback)
end

return LanguageBranching
