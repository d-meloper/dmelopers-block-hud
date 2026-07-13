return function(app)
    local loadRuntimeModule = app.loadRuntimeModule

    loadRuntimeModule('Render/Shared.lua')(app)
    loadRuntimeModule('Render/Geometry.lua')(app)
    loadRuntimeModule('Render/Layout.lua')(app)
    loadRuntimeModule('Render/Rows.lua')(app)
    loadRuntimeModule('Render/Page.lua')(app)
    loadRuntimeModule('Render/Dropdown.lua')(app)
    loadRuntimeModule('Render/Visuals.lua')(app)
end
