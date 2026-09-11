local network = require "telecom_network"

local REFRESH_SECONDS = 5
local SCRIPT = "telecom_growth.lua"
local EVENT_ID = "telecom_network"
local STATE_SCHEMA = 2
local SNAPSHOT_FIELDS = { "revision", "year", "nodes", "towns", "coverage", "bounds", "boundsEstimated",
    "globalBonus", "coveredTowns", "interval", "error" }

local function emptyState()
    return { schema = STATE_SCHEMA, revision = 0, nodes = {}, towns = {}, coverage = {},
        bounds = { minX = -128, maxX = 128, minY = -128, maxY = 128 },
        boundsEstimated = true, error = "En attente du premier calcul moteur" }
end

function data()
    -- Before the first successful scan, unknown year/metrics stay absent rather
    -- than displaying a fictional year or reporting a failed scan as zero coverage.
    local state = emptyState()
    local lastRefresh, ui
    local refreshRequested = false
    local exportRequested = false
    local cancelExportRequested = false
    local currentExportJob = nil
    local reportedErrors = {}

    local function report(message)
        message = tostring(message)
        if not reportedErrors[message] then
            print("[Telecom] " .. message)
            reportedErrors[message] = true
        end
    end

    local function guiError(err)
        return debug.traceback("Interface telecom: " .. tostring(err), 2)
    end

    local function refresh()
        lastRefresh = os.time()
        -- One transaction boundary: no partial snapshot/config on collection failure.
        local ok, result = pcall(function()
            local snapshot = network.computeSnapshot(network.collect(api, game.interface), state.revision + 1)
            snapshot.schema = STATE_SCHEMA
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
            state = emptyState()
            -- Discard pre-export snapshots and never restore obsolete map/UI caches.
            if type(loaded) == "table" and loaded.schema == STATE_SCHEMA
                and type(loaded.revision) == "number" and loaded.revision >= 0
                and loaded.revision < math.huge and loaded.revision % 1 == 0 then
                for _, key in ipairs(SNAPSHOT_FIELDS) do state[key] = loaded[key] end
                state.nodes, state.towns, state.coverage = state.nodes or {}, state.towns or {}, state.coverage or {}
            end
            -- Engine: immediate refresh after a saved game is loaded.
            -- GUI: only replace the snapshot; never collect or write game.config.
            lastRefresh = nil
        end,

        update = function()
            local now = os.time()
            if not lastRefresh or now < lastRefresh or now - lastRefresh >= REFRESH_SECONDS then refresh() end

            if currentExportJob then
                local ok, err = pcall(function() currentExportJob:step() end)
                if not ok then
                    state.exportStatus = { active = false, error = err }
                    currentExportJob = nil
                else
                    if currentExportJob.done then
                        state.exportStatus = {
                            active = false,
                            error = currentExportJob.error,
                            path = currentExportJob.path,
                            warnings = currentExportJob.warnings,
                        }
                        currentExportJob = nil
                    else
                        state.exportStatus = {
                            active = true,
                            progress = currentExportJob.progress,
                            phase = currentExportJob.phase,
                        }
                    end
                end
            end
        end,

        handleEvent = function(src, id, name, param)
            if id == EVENT_ID then
                if name == "refresh" then 
                    refresh() 
                elseif name == "export" then
                    if not currentExportJob then
                        local ok, result = pcall(function()
                            return require("telecom_export").new(state, { terrainResolution = 512 })
                        end)
                        if ok then
                            currentExportJob = result
                            state.exportStatus = { active = true, progress = 0, phase = "open" }
                        else
                            state.exportStatus = { active = false, error = result }
                        end
                    end
                elseif name == "cancelExport" then
                    if currentExportJob then
                        currentExportJob:cancel()
                        state.exportStatus = {
                            active = false,
                            message = currentExportJob.cleanupError and "Export annule, nettoyage incomplet" or "Export annule.",
                            tooltip = table.concat(currentExportJob.warnings or {}, "\n")
                        }
                        currentExportJob = nil
                    end
                end
            end
        end,

        guiInit = function()
            local ok, err = xpcall(function()
                local panel = require "telecom_panel"
                ui = panel.new(
                    function() refreshRequested = true end,
                    function() exportRequested = true end,
                    function() cancelExportRequested = true end
                )
            end, guiError)
            if not ok then
                report(err)
                local message = api.gui.comp.TextView.new("Telecom: " .. tostring(err))
                local window = api.gui.comp.Window.new("Telecom - Erreur d'interface", message)
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
            if exportRequested then
                api.cmd.sendCommand(api.cmd.make.sendScriptEvent(SCRIPT, EVENT_ID, "export", {}))
                exportRequested = false
            end
            if cancelExportRequested then
                api.cmd.sendCommand(api.cmd.make.sendScriptEvent(SCRIPT, EVENT_ID, "cancelExport", {}))
                cancelExportRequested = false
            end
            if ui then
                local ok, err = xpcall(function() ui:update(state) end, guiError)
                if not ok then report(err); ui:showError(err) end
            end
        end,

        guiHandleEvent = function(id, name, param)
            if name == "builder.apply" then
                refreshRequested = true
            end
        end,
    }
end
