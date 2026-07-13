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

    return schema
end
