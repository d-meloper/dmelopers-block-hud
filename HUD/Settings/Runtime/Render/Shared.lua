return function(app)
    local methods = app.methods
    local trim = app.trim

    local function contractVariable(name, fallback)
        return SKIN:GetVariable(name, fallback or '')
    end

    local function dropdownClosedText(rowIndex)
        return contractVariable('SettingsDropdownArrowClosed', contractVariable('SettingsRow' .. rowIndex .. '_DropdownButtonText', 'v'))
    end

    local function dropdownOpenText()
        return contractVariable('SettingsDropdownArrowOpen', '^')
    end

    local function pixelValue(value, fallback)
        local numeric = tonumber(value)
        if numeric == nil then
            numeric = tonumber(fallback) or 0
        end
        if numeric < 0 then
            return math.ceil(numeric - 0.5)
        end
        return math.floor(numeric + 0.5)
    end

    local function applyTextFit(meterName, text, baseFontVariable, width, height, policy)
        if not app.textFitter then
            return nil
        end
        return app.textFitter:Apply({
            meterName = meterName,
            text = text,
            baseFontSize = methods.numericVariable(baseFontVariable, 10) or 10,
            widthPx = width,
            heightPx = height,
            policy = policy or 'wrap4',
        })
    end

    function methods.numericVariable(name, fallback)

        local replaced = SKIN:ReplaceVariables('#' .. tostring(name) .. '#')

        local numeric = tonumber(trim(replaced))

        if numeric ~= nil then

            return numeric

        end

        local ok, parsed = pcall(function()

            return SKIN:ParseFormula(replaced)

        end)

        if ok and parsed ~= nil then

            numeric = tonumber(parsed)

            if numeric ~= nil then

                return numeric

            end

        end

        return fallback

    end
    app.renderHelpers = {
        contractVariable = contractVariable,
        dropdownClosedText = dropdownClosedText,
        dropdownOpenText = dropdownOpenText,
        pixelValue = pixelValue,
        applyTextFit = applyTextFit,
    }
end
