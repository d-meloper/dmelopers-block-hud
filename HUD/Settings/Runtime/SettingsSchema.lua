return function(loadRuntimeModule)
    local schema = {}

    local function merge(part)
        for key, value in pairs(part or {}) do
            schema[key] = value
        end
    end

    merge(loadRuntimeModule('Schema/Core.lua'))
    merge(loadRuntimeModule('Schema/Tabs.lua'))
    merge(loadRuntimeModule('Schema/Fields.lua'))
    merge(loadRuntimeModule('Schema/Options.lua'))

    local hudMirror = loadRuntimeModule('Schema/HudMirror.lua')
    for fieldKey, field in pairs(hudMirror.fields or {}) do
        schema.fields[fieldKey] = field
    end
    for _, fieldKey in ipairs(hudMirror.trackedFieldKeys or {}) do
        schema.trackedFieldKeys[#schema.trackedFieldKeys + 1] = fieldKey
    end

    return schema
end
