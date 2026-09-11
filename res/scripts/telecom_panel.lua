-- Export controls only. No native map, geometry cache or camera/ComboBox bindings.
local M = {}

function M.new(requestRefresh, requestExport, cancelExport)
    local comp, layout, util = api.gui.comp, api.gui.layout, api.gui.util
    local self = {}
    local snapshot, message, tooltip
    local outer = layout.BoxLayout.new("VERTICAL")
    local summary = comp.TextView.new(_("Chargement des donnees telecom..."))
    summary:setMaximumSize(util.Size.new(600, 70))
    outer:addItem(summary)
    outer:addItem(comp.TextView.new(_("Exporter une carte HTML autonome, puis l'ouvrir dans un navigateur.\nLes filtres, le zoom et les couvertures sont disponibles dans cette carte.")))
    local controls = layout.BoxLayout.new("HORIZONTAL")
    local function button(text, callback)
        local b = comp.Button.new(comp.TextView.new(_(text)), false)
        b:onClick(callback)
        controls:addItem(b)
        return b
    end
    local refresh = button("Actualiser", requestRefresh)
    local export = button("Exporter HTML", function()
        if not snapshot or snapshot.error or not snapshot.year then return end
        if snapshot.exportStatus and snapshot.exportStatus.active then return end
        message, tooltip = _("Export demande au moteur..."), ""
        if requestExport then requestExport() end
    end)
    local cancel = button("Annuler export", function()
        if not snapshot or not snapshot.exportStatus or not snapshot.exportStatus.active then return end
        message, tooltip = _("Annulation demandee..."), ""
        if cancelExport then cancelExport() end
    end)
    export:setEnabled(false)
    cancel:setEnabled(false)
    outer:addItem(controls)
    local status = comp.TextView.new("")
    status:setMaximumSize(util.Size.new(600, 100))
    if type(status.setSelectable) == "function" then status:setSelectable(true) end
    outer:addItem(status)
    outer:addItem(comp.TextView.new(_("Destination : dossier map_exports du mod.\nFermer cette fenetre laisse l'export continuer. Annuler export l'arrete.")))
    local window = comp.Window.new(_("Telecom - Export de couverture"), outer)
    window:setId("telecom_export_window")
    window:addHideOnCloseHandler()
    if type(window.setMovable) == "function" then window:setMovable(true) end
    window:setResizable(false)
    window:setVisible(false, false)
    local toggle = comp.Button.new(comp.TextView.new(_("Telecom")), false)
    toggle:setId("telecom_toggle_btn")
    toggle:setTooltip(_("Exporter la carte de couverture telecom"))
    toggle:onClick(function()
        window:setVisible(not window:isVisible(), true)
        if window:isVisible() then requestRefresh() end
    end)
    local gameInfo = util.getById("gameInfo")
    if gameInfo and gameInfo:getLayout() then
        gameInfo:getLayout():addItem(toggle)
    else
        window:setVisible(true, false)
    end

    function self:showError(err)
        summary:setText(_("Interface indisponible (voir journal)"))
        summary:setTooltip(tostring(err))
        export:setEnabled(false)
    end

    function self:update(state)
        snapshot = state
        local active = state and state.exportStatus and state.exportStatus.active

        if state and state.exportStatus then
            local status = state.exportStatus
            if not status.active and status.error then
                message = _("Export impossible (voir details)")
                tooltip = tostring(status.error) .. "\n" .. (status.warnings and table.concat(status.warnings, "\n") or "")
            elseif not status.active and status.path then
                message = _("Carte exportee : ") .. tostring(status.path)
                tooltip = tostring(status.path) .. "\n" .. (status.warnings and table.concat(status.warnings, "\n") or "")
            elseif status.active then
                message = string.format(_("Export : %.0f%% | %s"), 100 * (status.progress or 0), status.phase or "")
            elseif status.message then
                message = status.message
                tooltip = status.tooltip or ""
            end
        end
        if not window:isVisible() then return end
        local ready = state ~= nil and state.year ~= nil and not state.error
        export:setEnabled(ready and not active)
        cancel:setEnabled(active)
        refresh:setEnabled(not active)
        if ready then
            summary:setText(string.format(_("Annee %d | Equipements %d | Villes couvertes %d / %d\nBonus global calcule : %.1f%%"),
                state.year, #state.nodes, state.coveredTowns, #state.towns, 100 * state.globalBonus))
        else
            summary:setText(_("Donnees en attente : actualiser ou reprendre la simulation."))
        end
        summary:setTooltip(state and state.error or "")
        status:setText(message or "")
        status:setTooltip(tooltip or "")
    end
    return self
end

return M
