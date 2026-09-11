local ssu = require "stylesheetutil"

function data()
    local result = {}
    local add = ssu.makeAdder(result)
    add("TelecomMap", {
        backgroundColor = { 0.045, 0.065, 0.085, 1 },
        padding = { 0, 0, 0, 0 },
        margin = { 0, 0, 0, 0 },
    })
    add("TelecomMap LineRenderView", {
        backgroundColor = { 0, 0, 0, 0 },
        padding = { 0, 0, 0, 0 },
        margin = { 0, 0, 0, 0 },
    })
    add("TelecomMapLabel", {
        fontSize = 11,
        color = { 0.9, 0.94, 0.98, 1 },
        backgroundColor = { 0.045, 0.065, 0.085, 0.8 },
        padding = { 0, 2, 0, 2 },
    })
    return result
end
