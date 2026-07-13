return function(app)
    local state = app.state
    local schema = app.schema
    local methods = app.methods
    local trim = app.trim
    local shallowCopy = app.shallowCopy
    local logNotice = app.logNotice
    local setVariable = app.setVariable
    local MINECRAFT_SKIN_HISTORY_LIMIT = 12
    local MINECRAFT_USERNAME_PATTERN = '^[A-Za-z0-9_]+$'

    function methods.minecraftSkinImagePathForUsername(username)

        local sanitized = methods.sanitizeMinecraftSkinFileComponent(username)

        if sanitized == '' then

            return ''

        end

        return methods.playerSkinImageDirectoryPath() .. '\\MinecraftSkinBody_' .. sanitized .. '.png'

    end

    function methods.minecraftSkinTexturePathForUsername(username)

        local sanitized = methods.sanitizeMinecraftSkinFileComponent(username)

        if sanitized == '' then

            return ''

        end

        return methods.playerSkinImageDirectoryPath() .. '\\MinecraftSkinTexture_' .. sanitized .. '.png'

    end

    function methods.isBuiltInMinecraftSkinUsername(username)

        return string.lower(trim(tostring(username or ''))) == 'alex'

    end

    function methods.isLocalAttachedMinecraftSkinUsername(username)

        return string.lower(trim(tostring(username or ''))) == 'a'

    end

    function methods.shouldKeepMinecraftSkinHistoryName(username)

        local resolved = trim(tostring(username or ''))

        return resolved ~= ''
            and not methods.isBuiltInMinecraftSkinUsername(resolved)
            and not methods.isLocalAttachedMinecraftSkinUsername(resolved)

    end

    function methods.isValidMinecraftSkinUsername(username)

        local resolved = trim(tostring(username or ''))

        if resolved == '' then

            return true

        end

        return #resolved >= 3 and #resolved <= 16 and resolved:match(MINECRAFT_USERNAME_PATTERN) ~= nil

    end

    function methods.minecraftSkinInvalidUsernameMessage()

        return methods.localize('Helper_Minecraft_InvalidUsername', 'Enter a valid Minecraft username.')

    end

    function methods.sameNormalizedPath(left, right)

        local leftValue = trim(tostring(left or '')):gsub('/', '\\'):lower()

        local rightValue = trim(tostring(right or '')):gsub('/', '\\'):lower()

        return leftValue ~= '' and rightValue ~= '' and leftValue == rightValue

    end

    function methods.isPlayerSkinCachePngPath(path)

        local resolved = trim(tostring(path or ''))

        if resolved == '' or resolved:lower():match('%.png$') == nil then

            return false

        end

        local directory = resolved:match('^(.*)[\\/]') or ''

        if not methods.sameNormalizedPath(directory, methods.playerSkinImageDirectoryPath()) then

            return false

        end

        -- Helper-verified cache paths should not be rejected by Lua io.open on non-ANSI roots.
        return true

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

        if candidateImagePath ~= '' and methods.isPlayerSkinCachePngPath(candidateImagePath) then

            return candidateImagePath

        end
        if candidateImagePath ~= '' and expectedImagePath ~= '' and methods.sameNormalizedPath(candidateImagePath, expectedImagePath) and (methods.isPlayerSkinCachePngPath(candidateImagePath) or methods.isPngFile(candidateImagePath) or (allowStoredWidePath and methods.isStoredWidePngPath(candidateImagePath))) then

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

        if candidateImagePath ~= '' and methods.isPlayerSkinCachePngPath(candidateImagePath) then

            return candidateImagePath

        end
        if candidateImagePath ~= '' and expectedImagePath ~= '' and methods.sameNormalizedPath(candidateImagePath, expectedImagePath) and (methods.isPlayerSkinCachePngPath(candidateImagePath) or methods.isPngFile(candidateImagePath) or (allowStoredWidePath and methods.isStoredWidePngPath(candidateImagePath))) then

            return candidateImagePath

        end

        if expectedImagePath ~= '' and methods.isPngFile(expectedImagePath) then

            return expectedImagePath

        end

        return ''

    end

    function methods.resolveStoredMinecraftSkinTexturePath(username, texturePath, options)

        local resolvedUsername = trim(tostring(username or ''))

        if resolvedUsername == '' then

            return ''

        end

        options = options or {}

        local allowStoredTexturePath = options.allowStoredTexturePath == true

        local expectedTexturePath = methods.minecraftSkinTexturePathForUsername(resolvedUsername)

        local candidateTexturePath = trim(tostring(texturePath or ''))

        if candidateTexturePath ~= '' and methods.isPlayerSkinCachePngPath(candidateTexturePath) then

            return candidateTexturePath

        end
        if candidateTexturePath ~= '' and expectedTexturePath ~= '' and methods.sameNormalizedPath(candidateTexturePath, expectedTexturePath) and (methods.isPlayerSkinCachePngPath(candidateTexturePath) or methods.isPngFile(candidateTexturePath) or (allowStoredTexturePath and methods.isStoredWidePngPath(candidateTexturePath))) then

            return candidateTexturePath

        end

        if expectedTexturePath ~= '' and (methods.isPngFile(expectedTexturePath) or (allowStoredTexturePath and methods.isStoredWidePngPath(expectedTexturePath))) then

            return expectedTexturePath

        end

        return ''

    end

    function methods.resolveCurrentMinecraftSkinTexturePath(username)

        local resolvedUsername = trim(tostring(username or ''))

        if resolvedUsername == '' then

            local field = methods.getField('minecraftSkinUsername')

            resolvedUsername = field and trim(methods.readFieldValue(field)) or ''

        end

        local storedImagePath = SKIN:GetVariable('MinecraftSkinImagePath', '')

        return methods.resolveStoredMinecraftSkinTexturePath(resolvedUsername, SKIN:GetVariable('MinecraftSkinTexturePath', ''), {

            allowStoredTexturePath = methods.isMinecraftSkinImagePathVerified(storedImagePath),

        })

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

        local resolvedImagePathVerified = resolvedImagePath ~= '' and storedImagePathVerified

        if (storedImagePath ~= '' or resolvedImagePath ~= '') and not methods.sameNormalizedPath(storedImagePath, resolvedImagePath) then

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePath', resolvedImagePath)

            setVariable('MinecraftSkinImagePath', resolvedImagePath)

        end

        if trim(SKIN:GetVariable('MinecraftSkinImagePathVerified', '0')) ~= (resolvedImagePathVerified and '1' or '0') then

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinImagePathVerified', resolvedImagePathVerified and '1' or '0')

            setVariable('MinecraftSkinImagePathVerified', resolvedImagePathVerified and '1' or '0')

        end

        local storedTexturePath = trim(SKIN:GetVariable('MinecraftSkinTexturePath', ''))

        local resolvedTexturePath = methods.resolveStoredMinecraftSkinTexturePath(username, storedTexturePath, {

            allowStoredTexturePath = storedImagePathVerified,

        })

        if (storedTexturePath ~= '' or resolvedTexturePath ~= '') and not methods.sameNormalizedPath(storedTexturePath, resolvedTexturePath) then

            methods.writeIniVariable(methods.settingsFilePath('Support'), 'MinecraftSkinTexturePath', resolvedTexturePath)

            setVariable('MinecraftSkinTexturePath', resolvedTexturePath)

        end

        local draftUsername = username

        if methods.isLocalAttachedMinecraftSkinUsername(username) then

            draftUsername = ''

        end

        return methods.syncMinecraftSkinDraft(draftUsername)

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

            if methods.shouldKeepMinecraftSkinHistoryName(trimmedEntry) and not seen[key] then

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

            if methods.shouldKeepMinecraftSkinHistoryName(trimmedEntry) and not seen[key] then

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

        if not methods.shouldKeepMinecraftSkinHistoryName(resolved) then

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

            if methods.shouldKeepMinecraftSkinHistoryName(trimmedEntry) and not seen[key] then

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

        local canonicalStoredTexturePath = SKIN:GetVariable('MinecraftSkinTexturePath', '')

        local canonicalImagePath = methods.resolveVerifiedLocalMinecraftSkinImagePath(canonicalUsername, canonicalStoredImagePath, { allowStoredWidePath = methods.isMinecraftSkinImagePathVerified(canonicalStoredImagePath) })

        local canonicalTexturePath = methods.resolveStoredMinecraftSkinTexturePath(canonicalUsername, canonicalStoredTexturePath, {

            allowStoredTexturePath = methods.isMinecraftSkinImagePathVerified(canonicalStoredImagePath),

        })

        local requestedKey = string.lower(resolved)

        local canonicalKey = string.lower(canonicalUsername)

        local hasCanonicalPng = canonicalImagePath ~= ''

        methods.appendMinecraftSkinDebugLog('resolveLocalMinecraftSkinResult username=' .. resolved .. ' canonicalUsername=' .. canonicalUsername .. ' canonicalImagePath=' .. tostring(canonicalImagePath) .. ' hasCanonicalPng=' .. tostring(hasCanonicalPng))

        if canonicalKey ~= '' and canonicalKey == requestedKey and hasCanonicalPng then

            return {

                status = 'OK',

                username = canonicalUsername,

                imagePath = canonicalImagePath,

                texturePath = canonicalTexturePath,

                message = '',

            }

        end

        local imagePath = methods.minecraftSkinImagePathForUsername(resolved)

        local storedImagePath = SKIN:GetVariable('MinecraftSkinImagePath', '')

        local texturePath = methods.resolveStoredMinecraftSkinTexturePath(resolved, SKIN:GetVariable('MinecraftSkinTexturePath', ''), {

            allowStoredTexturePath = methods.isMinecraftSkinImagePathVerified(storedImagePath),

        })

        local hasPng = imagePath ~= '' and methods.isPngFile(imagePath)

        methods.appendMinecraftSkinDebugLog('resolveLocalMinecraftSkinResult username=' .. resolved .. ' path=' .. tostring(imagePath) .. ' hasPng=' .. tostring(hasPng))

        if hasPng then

            return {

                status = 'OK',

                username = resolved,

                imagePath = imagePath,

                texturePath = texturePath,

                message = '',

            }

        end

        return nil

    end
end
