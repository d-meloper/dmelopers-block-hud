return function(app)
    local loadRuntimeModule = app.loadRuntimeModule

    loadRuntimeModule('Cache/Common.lua')(app)
    loadRuntimeModule('Cache/State.lua')(app)
    loadRuntimeModule('Cache/Helpers.lua')(app)
    loadRuntimeModule('Cache/Data.lua')(app)
    loadRuntimeModule('Cache/MinecraftSkin.lua')(app)
    loadRuntimeModule('Cache/Completions.lua')(app)
    loadRuntimeModule('Cache/PendingLoad.lua')(app)
end
