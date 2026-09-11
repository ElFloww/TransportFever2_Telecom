local network = require "telecom_network"

local REFRESH_SECONDS = 5
local SCRIPT = "telecom_growth.lua"
local EVENT_ID = "telecom_network"

function data()
    -- Before the first successful scan, unknown year/metrics stay absent rather
    -- than displaying a fictional year or reporting a failed scan as zero coverage.
    local state = {
        revision = 0, nodes = {}, towns = {}, coverage = {},
        bounds = { minX = -128, maxX = 128, minY = -128, maxY = 128 },
        boundsEstimated = true, error = "En attente du premier calcul moteur",
    }
    local lastRefresh, ui
    local refreshRequested = false
    local reportedErrors = {}

    local function report(message)
        message = tostring(message)
        if not reportedErrors[message] then
            print("[Telecom] " .. message)
            reportedErrors[message] = true
        end
    end

    local function refresh()
        lastRefresh = os.time()
        -- One transaction boundary: no partial snapshot/config on collection failure.
        local ok, result = pcall(function()
            local snapshot = network.computeSnapshot(network.collect(api, game.interface), state.revision + 1)
            assert(game.config, "game.config indisponible")
            -- Retains the existing global setting; its runtime effect needs in-game validation.
            game.config.townDevelopInterval = snapshot.interval
            return snapshot
        end)
        if ok then
            state = result
        else
            local message = tostring(result)
            report(message)
            if state.error ~= message then
                local failed = {}
                for key, value in pairs(state) do failed[key] = value end
                failed.revision, failed.error = state.revision + 1, message
                state = failed
            end
        end
    end

    return {
        save = function()
            return state
        end,

        load = function(loaded)
            if type(loaded) == "table" and type(loaded.revision) == "number" then state = loaded end
            -- Engine: immediate refresh after a saved game is loaded.
            -- GUI: only replace the snapshot; never collect or write game.config.
            lastRefresh = nil
        end,

        update = function()
            local now = os.time()
            if not lastRefresh or now < lastRefresh or now - lastRefresh >= REFRESH_SECONDS then refresh() end
        end,

        handleEvent = function(src, id, name, param)
            if id == EVENT_ID and name == "refresh" then refresh() end
        end,

        guiInit = function()
            local ok, err = pcall(function()
                local map = require "telecom_map"
                ui = map.new(function() refreshRequested = true end)
            end)
            if not ok then
                report(err)
                local message = api.gui.comp.TextView.new("Telecom: " .. tostring(err))
                local window = api.gui.comp.Window.new("Telecom - Erreur de carte", message)
                window:addHideOnCloseHandler()
                window:setVisible(true, false)
            end
            refreshRequested = true
        end,

        guiUpdate = function()
            -- sendScriptEvent must run inside a script callback, not a button callback.
            -- In pause, requests wait for the engine if necessary; no GUI preview/calculation.
            if refreshRequested then
                api.cmd.sendCommand(api.cmd.make.sendScriptEvent(SCRIPT, EVENT_ID, "refresh", {}))
                refreshRequested = false
            end
            if ui then
                local ok, err = pcall(function() ui:update(state) end)
                if not ok then report(err); ui:showError(err) end
            end
        end,

        guiHandleEvent = function(id, name, param)
            if name == "builder.apply" then
                refreshRequested = true
                if ui and ui.invalidateBackground then ui:invalidateBackground() end
            end
        end,
    }
end
