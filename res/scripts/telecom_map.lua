local geometry = require "telecom_map_geometry"
local background = require "telecom_map_background"
local network = require "telecom_network"
local M = {}

local colors = {
    NRA = { 0.25, 0.65, 1, 1 }, NRO = { 0.8, 0.5, 1, 1 },
    ANTENNA = { 1, 0.65, 0.2, 1 }, inactive = { 0.5, 0.55, 0.6, 1 },
    tech_2g = { 1, 0.78, 0.25, 0.85 }, tech_3g = { 0.3, 0.85, 0.8, 0.85 },
    tech_3gp = { 0.25, 0.7, 1, 0.85 }, tech_4g = { 0.55, 0.85, 0.3, 0.85 },
    tech_4gp = { 0.9, 0.8, 0.4, 0.85 }, tech_5g = { 1, 0.45, 0.4, 0.85 },
    tech_5gp = { 1, 0.45, 0.8, 0.85 }, town = { 0.8, 0.84, 0.9, 1 },
    covered = { 0.45, 1, 0.7, 1 }, selected = { 1, 1, 1, 1 },
    grid = { 0.2, 0.28, 0.34, 0.6 }, water = { 0.2, 0.45, 0.65, 0.65 },
    low = { 0.22, 0.38, 0.29, 0.5 }, hill = { 0.38, 0.4, 0.29, 0.5 },
    high = { 0.5, 0.47, 0.4, 0.5 }, road = { 0.5, 0.53, 0.57, 0.5 },
    rail = { 0.72, 0.65, 0.52, 0.7 },
}

local function find(items, id)
    for _, item in ipairs(items or {}) do if item.id == id then return item end end
end

local function active(node)
    for _, service in ipairs(node.services) do if service.active then return true end end
    return false
end

function M.new(requestRefresh)
    local comp, layout, util = api.gui.comp, api.gui.layout, api.gui.util
    local W, H = 720, 300
    local self = { zoom = 1, dirty = true, filters = { NRA = true, NRO = true, ANTENNA = true },
        showTowns = true, showNames = true, showTerrain = true, showRoads = true, showRails = true,
        selectedOnly = false, hatch = false }
    for _, tech in ipairs(network.techs) do self.filters[tech.key] = true end
    local outer = layout.BoxLayout.new("VERTICAL")
    local summary = comp.TextView.new(_("Chargement des donnees telecom..."))
    summary:setMaximumSize(util.Size.new(W, 48))
    outer:addItem(summary)

    local canvas = comp.Component.new("TelecomMap")
    canvas:setId("telecom_map_canvas")
    canvas:setMinimumSize(util.Size.new(W, H))
    canvas:setMaximumSize(util.Size.new(W, H))
    local absolute = layout.AbsoluteLayout.new()
    canvas:setLayout(absolute)
    local planes, planeComponents = {}, {}
    for _, name in ipairs({ "context", "coverage", "markers", "labels" }) do
        local plane = comp.Component.new("TelecomMapPlane")
        local planeLayout = layout.AbsoluteLayout.new()
        plane:setLayout(planeLayout)
        absolute:addItem(plane, util.Rect.new(0, 0, W, H))
        planes[name] = planeLayout
        planeComponents[#planeComponents + 1] = plane
    end
    local layers, visibleItems, dropdownItems = {}, {}, {}
    local status = comp.TextView.new("")
    status:setMaximumSize(util.Size.new(W, 44))
    local details = comp.TextView.new(_("Selectionnez un equipement ou une ville sur la carte."))
    local dropdown = comp.ComboBox.new()
    dropdown:setMaximumSize(util.Size.new(380, 32))
    local rebuildingDropdown = false
    local selected, selectedType, drag, suppressClick, cameraError
    local bg, bgPending, bgCompleted, bgKey, dropdownKey
    local snapshot, view
    local mouseListener

    local function button(row, text, callback)
        local b = comp.Button.new(comp.TextView.new(_(text)), false)
        b:onClick(callback)
        row:addItem(b)
        return b
    end
    local function checkbox(row, text, value, callback, colorKey)
        local box = comp.CheckBox.new(_(text))
        box:setSelected(value, false)
        box:onToggle(function(on) callback(on); self.dirty = true end)
        if colorKey then
            local swatch = comp.LineRenderView.new()
            swatch:setMinimumSize(util.Size.new(16, 16))
            swatch:setMaximumSize(util.Size.new(16, 16))
            swatch:setColor(api.type.Vec4f.new(table.unpack(colors[colorKey])))
            swatch:setWidth(2)
            geometry.marker(function(x0, y0, x1, y1)
                swatch:addLine(api.type.Vec2f.new(x0, y0), api.type.Vec2f.new(x1, y1))
            end, colorKey:find("tech_", 1, true) and "ANTENNA" or colorKey, 8, 8, 5)
            row:addItem(swatch)
        end
        row:addItem(box)
        return box
    end
    local function resetView()
        self.zoom, self.cx, self.cy, self.dirty = 1, nil, nil, true
    end
    local function zoom(factor, x, y)
        if not view then return end
        local wx, wy = geometry.unproject(view, x or W / 2, y or H / 2)
        local old = self.zoom
        self.zoom = math.max(1, math.min(32, old * factor))
        self.cx = wx - (wx - view.cx) * old / self.zoom
        self.cy = wy - (wy - view.cy) * old / self.zoom
        if self.zoom == 1 then self.cx, self.cy = nil, nil end
        self.dirty = true
    end
    local function selection(item, kind)
        selected, selectedType = item and item.id, kind
        cameraError = nil
        self.dirty = true
    end
    local function getSelected()
        return snapshot and find(selectedType == "town" and snapshot.towns or snapshot.nodes, selected)
    end

    local kinds = layout.BoxLayout.new("HORIZONTAL")
    checkbox(kinds, "NRA", true, function(on) self.filters.NRA = on end, "NRA")
    checkbox(kinds, "NRO", true, function(on) self.filters.NRO = on end, "NRO")
    checkbox(kinds, "Antennes", true, function(on) self.filters.ANTENNA = on end, "ANTENNA")
    checkbox(kinds, "Villes", true, function(on) self.showTowns = on end, "town")
    checkbox(kinds, "Noms", true, function(on) self.showNames = on end)
    outer:addItem(kinds)
    local techRow = layout.BoxLayout.new("HORIZONTAL")
    for _, tech in ipairs(network.techs) do
        local key = tech.key
        checkbox(techRow, tech.name, true, function(on) self.filters[key] = on end, key)
    end
    outer:addItem(techRow)
    local controls = layout.BoxLayout.new("HORIZONTAL")
    button(controls, "+", function() zoom(1.5) end)
    button(controls, "-", function() zoom(1 / 1.5) end)
    button(controls, "Carte entiere", resetView)
    checkbox(controls, "Couverture : selection", false, function(on) self.selectedOnly = on end)
    checkbox(controls, "Hachures", false, function(on) self.hatch = on end)
    outer:addItem(controls)
    local context = layout.BoxLayout.new("HORIZONTAL")
    checkbox(context, "Relief / eau", true, function(on) self.showTerrain = on end)
    checkbox(context, "Routes", true, function(on) self.showRoads = on end)
    checkbox(context, "Rails", true, function(on) self.showRails = on end)
    button(context, "Actualiser", function()
        self:invalidateBackground()
        requestRefresh()
    end)
    outer:addItem(context)
    outer:addItem(canvas)
    outer:addItem(status)

    local selectRow = layout.BoxLayout.new("HORIZONTAL")
    selectRow:addItem(dropdown)
    local locate = button(selectRow, "Voir en jeu", function()
        local item = getSelected()
        if not item or not api.engine.entityExists(item.id) then return end
        local ok, err = pcall(function()
            util.getGameUI():getMainRendererComponent():getCameraController():focus(item.id)
        end)
        cameraError = not ok and tostring(err) or nil
        if not ok then
            status:setText(_("Camera indisponible (voir journal)"))
            status:setTooltip(cameraError)
            print("[Telecom map] camera: " .. tostring(err))
        end
    end)
    local center = button(selectRow, "Centrer carte", function()
        local item = getSelected()
        if item then
            self.cx, self.cy, self.zoom, self.dirty = item.x, item.y, math.max(4, self.zoom), true
        end
    end)
    outer:addItem(selectRow)
    local scroll = comp.ScrollArea.new(details)
    scroll:setMinimumSize(util.Size.new(W, 82))
    scroll:setMaximumSize(util.Size.new(W, 82))
    outer:addItem(scroll)
    outer:addItem(comp.TextView.new(_("Portee theorique, sans relief. Croix verte : centre de ville couvert.")))

    local window = comp.Window.new(_("Telecom - Carte de couverture"), outer)
    window:setId("telecom_status_window")
    window:addHideOnCloseHandler()
    window:setMovable(true)
    window:setResizable(false)
    window:setVisible(false, false)
    window:onVisibilityChange(function(visible)
        drag = nil
        if visible then self.dirty = true end
    end)
    self.window = window
    local toggle = comp.Button.new(comp.TextView.new(_("Telecom")), false)
    toggle:setId("telecom_toggle_btn")
    toggle:setTooltip(_("Afficher la carte de couverture telecom"))
    toggle:onClick(function()
        window:setVisible(not window:isVisible(), true)
        if window:isVisible() then requestRefresh(); self.dirty = true end
    end)
    local gameInfo = util.getById("gameInfo")
    if gameInfo and gameInfo:getLayout() then
        gameInfo:getLayout():addItem(toggle)
    else
        window:setVisible(true, false)
        print("[Telecom map] gameInfo absent; carte ouverte sans bouton.")
    end

    dropdown:onIndexChanged(function(index)
        if rebuildingDropdown then return end
        local item = dropdownItems[index + 1]
        selection(item and item.item, item and item.kind)
    end)

    mouseListener = function(event)
        if not view then return false end
        local rect, mouse = canvas:getContentRect(), util.getMouseScreenPos()
        if rect.w <= 0 or rect.h <= 0 then return false end
        local x, y = (mouse.x - rect.x) * W / rect.w, (mouse.y - rect.y) * H / rect.h
        if event.type == 0 and event.button == 0 then
            drag = { x = x, y = y, cx = view.cx, cy = view.cy, moved = false }
            suppressClick = false
            return true
        elseif event.type == 5 and drag then
            if math.abs(x - drag.x) + math.abs(y - drag.y) > 4 then drag.moved = true end
            if drag.moved then
                self.cx = drag.cx - (x - drag.x) / view.scale
                self.cy = drag.cy + (y - drag.y) / view.scale
                self.dirty = true
            end
            return true
        elseif event.type == 1 and event.button == 0 then
            suppressClick = drag and drag.moved
            drag = nil
            return true
        elseif event.type == 4 and (x < 0 or y < 0 or x > W or y > H) then
            drag = nil
        elseif event.type == 2 and event.button == 0 then
            if not suppressClick then
                local hit = geometry.hitTest(visibleItems, view, x, y, 10)
                selection(hit, hit and hit.kind == "TOWN" and "town" or "node")
            end
            suppressClick = false
            return true
        end
        return false
    end
    canvas:setMouseListener(mouseListener)
    for _, plane in ipairs(planeComponents) do plane:setMouseListener(mouseListener) end
    canvas:setTooltip(_("Glisser pour deplacer. Boutons + / - pour zoomer. Cliquer pour selectionner."))

    -- A pool per colour avoids changing previously drawn lines. Chunking keeps
    -- each native renderer below the large vertex buffers seen on dense maps.
    local function lineWriter(key, width, alpha, budget)
        local poolKey = budget.plane .. ":" .. key .. ":" .. width .. ":" .. (alpha or 1)
        local pool = layers[poolKey]
        if not pool then pool = { used = 0, views = {} }; layers[poolKey] = pool end
        return function(x0, y0, x1, y1)
            x0, y0, x1, y1 = geometry.clip(x0, y0, x1, y1, W, H)
            if not x0 then return end
            if budget.remaining <= 0 then self.limited = true; return end
            budget.remaining = budget.remaining - 1
            local index = math.floor(pool.used / 1500) + 1
            local renderer = pool.views[index]
            if not renderer then
                renderer = comp.LineRenderView.new()
                renderer:setColor(api.type.Vec4f.new(colors[key][1], colors[key][2], colors[key][3],
                    colors[key][4] * (alpha or 1)))
                renderer:setWidth(width)
                renderer:setMouseListener(mouseListener)
                planes[budget.plane]:addItem(renderer, util.Rect.new(0, 0, W, H))
                pool.views[index] = renderer
            end
            renderer:addLine(api.type.Vec2f.new(x0, y0), api.type.Vec2f.new(x1, y1))
            pool.used = pool.used + 1
        end
    end

    local labels = {}
    local function clearLabels()
        for _, label in ipairs(labels) do
            local item = planes.labels:removeItem(planes.labels:getIndex(label))
            item:destroy()
        end
        labels = {}
    end
    local function label(text, x, y)
        if x < 0 or x + 8 > W or y < 0 or y + 16 > H or #labels >= 60 then return end
        local width = math.min(130, math.floor(W - x))
        local textView = comp.TextView.new(text)
        textView:setName("TelecomMapLabel")
        textView:setMaximumSize(util.Size.new(width, 16))
        textView:setMouseListener(mouseListener)
        planes.labels:addItem(textView, util.Rect.new(math.floor(x), math.floor(y), width, 16))
        labels[#labels + 1] = textView
    end

    function self:invalidateBackground()
        bg, bgPending, bgKey, bgCompleted, self.dirty = nil, nil, nil, nil, true
    end

    function self:showError(message)
        summary:setText(_("Carte indisponible (voir journal)"))
        summary:setTooltip(tostring(message))
    end

    local function render()
        self.limited = false
        for _, pool in pairs(layers) do
            pool.used = 0
            for _, renderer in ipairs(pool.views) do renderer:clear() end
        end
        clearLabels()
        visibleItems = {}
        view = geometry.view(snapshot.bounds, W, H, self.zoom, self.cx, self.cy)
        local contextBudget = { remaining = 7000, plane = "context" }
        local coverageBudget = { remaining = 16000, plane = "coverage" }
        local markerBudget = { remaining = 6000, plane = "markers" }
        local function worldLine(draw, x0, y0, x1, y1)
            local px, py = geometry.project(view, x0, y0)
            local qx, qy = geometry.project(view, x1, y1)
            draw(px, py, qx, qy)
        end
        local grid = lineWriter("grid", 1, 1, contextBudget)
        local b = snapshot.bounds
        worldLine(grid, b.minX, b.minY, b.maxX, b.minY)
        worldLine(grid, b.maxX, b.minY, b.maxX, b.maxY)
        worldLine(grid, b.maxX, b.maxY, b.minX, b.maxY)
        worldLine(grid, b.minX, b.maxY, b.minX, b.minY)
        if bg and bg.done then
            if self.showTerrain then
                local writers = {}
                for _, segment in ipairs(bg.terrain) do
                    if contextBudget.remaining <= 0 then self.limited = true; break end
                    local key = segment[5]
                    writers[key] = writers[key] or lineWriter(key, 1, 1, contextBudget)
                    worldLine(writers[key], table.unpack(segment, 1, 4))
                end
            end
            local minX, minY = geometry.unproject(view, 0, H)
            local maxX, maxY = geometry.unproject(view, W, 0)
            for _, group in ipairs({ { self.showRoads, "roads", "road" }, { self.showRails, "rails", "rail" } }) do
                if group[1] then
                    local draw = lineWriter(group[3], 1, 1, contextBudget)
                    for segment in bg:segments(group[2], math.max(b.minX, minX), math.max(b.minY, minY),
                        math.min(b.maxX, maxX), math.min(b.maxY, maxY)) do
                        if contextBudget.remaining <= 0 then self.limited = true; break end
                        worldLine(draw, table.unpack(segment))
                    end
                end
            end
        end
        for _, node in ipairs(snapshot.nodes) do
            if self.filters[node.kind] then
                visibleItems[#visibleItems + 1] = node
                local x, y = geometry.project(view, node.x, node.y)
                if not self.selectedOnly or (selectedType == "node" and node.id == selected) then
                    for _, service in ipairs(node.services) do
                        if service.active and self.filters[service.key] then
                            if coverageBudget.remaining <= 0 then self.limited = true; break end
                            local radius = service.radius * view.scale
                            if x + radius >= 0 and y + radius >= 0 and x - radius <= W and y - radius <= H then
                                local draw = lineWriter(service.key, 1, 1, coverageBudget)
                                geometry.circle(draw, x, y, radius)
                                if self.hatch then
                                    local hatch = lineWriter(service.key, 1, 0.25, coverageBudget)
                                    for yy = math.max(0, math.ceil((y - radius) / 10) * 10), math.min(H, y + radius), 10 do
                                        local half = math.sqrt(math.max(0, radius^2 - (yy - y)^2))
                                        hatch(x - half, yy, x + half, yy)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        -- Draw symbols after the coverage so small equipment remains legible.
        for _, node in ipairs(visibleItems) do
            local x, y = geometry.project(view, node.x, node.y)
            local key = active(node) and node.kind or "inactive"
            geometry.marker(lineWriter(key, 2, 1, markerBudget), node.kind, x, y, 5)
        end
        if self.showTowns then
            for _, town in ipairs(snapshot.towns) do
                local x, y = geometry.project(view, town.x, town.y)
                local coverage = snapshot.coverage[town.id]
                local key = coverage and (coverage.hasFixed or coverage.hasMobile) and "covered" or "town"
                geometry.marker(lineWriter(key, 2, 1, markerBudget), "TOWN", x, y, 4)
                visibleItems[#visibleItems + 1] = { id = town.id, kind = "TOWN", name = town.name, x = town.x, y = town.y }
                if self.showNames then label(town.name, x + 7, y - 8) end
            end
        end
        local item = getSelected()
        if item then
            local x, y = geometry.project(view, item.x, item.y)
            geometry.circle(lineWriter("selected", 2, 1, markerBudget), x, y, 10)
        end
        local scaleLine = lineWriter("selected", 2, 1, markerBudget)
        local metres = 10 ^ math.floor(math.log(100 / view.scale) / math.log(10))
        for _, multiplier in ipairs({ 5, 2, 1 }) do
            if metres * multiplier * view.scale <= 120 then metres = metres * multiplier; break end
        end
        local length = metres * view.scale
        scaleLine(12, H - 12, 12 + length, H - 12)
        scaleLine(12, H - 16, 12, H - 8)
        scaleLine(12 + length, H - 16, 12 + length, H - 8)
        label(string.format("%g m", metres), 12, H - 34)
        label("N", W - 24, 4)
        self.dirty = false
    end

    local function updateDetails()
        local item = getSelected()
        local index = 0
        if item then
            for i, choice in ipairs(dropdownItems) do
                if choice.item and choice.item.id == item.id and choice.kind == selectedType then index = i - 1; break end
            end
        end
        -- ComboBox uses setSelected(index, emit), not setCurrentIndex.
        dropdown:setSelected(index, false)
        locate:setEnabled(item ~= nil)
        center:setEnabled(item ~= nil)
        if not item then
            details:setText(_("Selectionnez un equipement ou une ville sur la carte."))
            return
        end
        local lines = { item.name .. "  (#" .. item.id .. ")",
            string.format("X : %.0f m | Y : %.0f m", item.x, item.y) }
        if selectedType == "town" then
            local coverage = snapshot.coverage[item.id]
            lines[#lines + 1] = string.format(_("Contributions : fixe %.0f%% | mobile %.0f%%"),
                100 * coverage.fixedBonus, 100 * coverage.mobileBonus)
            for _, node in ipairs(snapshot.nodes) do
                for _, service in ipairs(node.services) do
                    for _, townId in ipairs(service.townIds or {}) do
                        if townId == item.id then
                            lines[#lines + 1] = node.name .. " : " .. service.name
                        end
                    end
                end
            end
        else
            for serviceIndex, service in ipairs(item.services) do
                local state = service.active and _("actif") or service.configured
                    and string.format(_("disponible en %d"), service.year) or _("desactive")
                lines[#lines + 1] = string.format("%s : %d m | %s", service.name, service.radius, state)
                if service.active then
                    local names = {}
                    for _, id in ipairs(service.townIds or {}) do
                        local town = find(snapshot.towns, id)
                        if town then names[#names + 1] = town.name end
                    end
                    lines[#lines + 1] = _("Villes : ") .. (#names > 0 and table.concat(names, ", ") or _("aucune"))
                end
            end
        end
        details:setText(table.concat(lines, "\n"))
    end

    function self:update(state)
        if not window:isVisible() then return end
        if not state or not state.bounds or not state.year or state.globalBonus == nil then
            summary:setText(state and state.error and _("Donnees telecom en attente (voir journal)")
                or _("Chargement des donnees telecom..."))
            summary:setTooltip(state and state.error or "")
            return
        end
        summary:setTooltip(state.error or "")
        if not snapshot or snapshot.revision ~= state.revision then
            snapshot = state
            self.dirty = true
            if selected and not getSelected() then selection(nil, nil) end
            local counts = { NRA = 0, NRO = 0, ANTENNA = 0 }
            for _, node in ipairs(snapshot.nodes) do counts[node.kind] = counts[node.kind] + 1 end
            summary:setText(string.format(_("Annee %d | NRA %d | NRO %d | Antennes %d\nVilles couvertes : %d / %d | Bonus global calcule : %.1f%%"),
                snapshot.year, counts.NRA, counts.NRO, counts.ANTENNA,
                snapshot.coveredTowns, #snapshot.towns, 100 * snapshot.globalBonus))
            local keys = {}
            local choices = { { label = _("Selectionner..."), kind = nil } }
            for groupIndex, group in ipairs({ { snapshot.nodes, "node" }, { snapshot.towns, "town" } }) do
                for itemIndex, item in ipairs(group[1]) do
                    local text = (group[2] == "town" and _("Ville") or item.kind) .. " : " .. item.name .. " (#" .. item.id .. ")"
                    keys[#keys + 1] = text
                    choices[#choices + 1] = { label = text, item = item, kind = group[2] }
                end
            end
            local key = table.concat(keys, "\n")
            dropdownItems = choices
            if key ~= dropdownKey then
                rebuildingDropdown = true
                dropdown:clear()
                for _, choice in ipairs(choices) do dropdown:addItem(choice.label) end
                rebuildingDropdown = false
                dropdownKey = key
            end
        end
        local bounds = snapshot.bounds
        local key = table.concat({ bounds.minX, bounds.minY, bounds.maxX, bounds.maxY }, ":")
        if key ~= bgKey then
            bg, bgPending, bgCompleted = nil, nil, nil
        end
        if not bgPending and (not bg or not bgCompleted or os.time() - bgCompleted >= 60) then
            bgPending, bgKey = background.new(bounds), key
        end
        if bgPending and bgPending:step() then
            bg, bgPending, bgCompleted, self.dirty = bgPending, nil, os.time(), true
        end
        if self.dirty then render(); updateDetails() end
        local warnings = bg and bg.warnings or {}
        local messages = { string.format(_("Zoom x%.1f | Portee circulaire theorique"), self.zoom) }
        if snapshot.boundsEstimated then messages[#messages + 1] = _("Limites estimees") end
        local warning = state.error and _("Donnees non actualisees (voir journal)")
            or cameraError and _("Camera indisponible (voir journal)")
            or self.limited and _("Affichage limite : zoomez ou filtrez")
            or #warnings > 0 and _("Fond incomplet (voir journal)")
            or bgPending and _("Preparation du fond de carte...") or ""
        status:setText(table.concat(messages, " | ") .. "\n" .. warning)
        status:setTooltip(state.error or cameraError or table.concat(warnings, "\n"))
    end

    return self
end

return M
