-- Run from the repository root: lua tests/telecom_map_test.lua
-- Contract smoke tests, not a replacement for a TF2 native GUI/runtime test.
-- No stylesheet loader, game script, or permissive GUI method fallback is used.
-- GUI reference: https://transportfever2.com/wiki/api/modules/api.gui.html
package.path = "./res/scripts/?.lua;" .. package.path
local geometry = require "telecom_map_geometry"
local background = require "telecom_map_background"
local network = require "telecom_network"
local map = require "telecom_map"
local passed, failed = 0, 0

local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
        print("ok - " .. name)
    else
        failed = failed + 1
        print("not ok - " .. name .. "\n" .. tostring(err))
    end
end

local function near(actual, expected, epsilon)
    assert(type(actual) == "number" and math.abs(actual - expected) <= (epsilon or 1e-8),
        tostring(actual) .. " ~= " .. tostring(expected))
end

local function contains(text, expected)
    assert(type(text) == "string" and text:find(expected, 1, true),
        tostring(text) .. " does not contain " .. expected)
end

local function finite(value)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge,
        "expected a finite number")
end

local function collect(draw, ...)
    local lines = {}
    draw(function(x0, y0, x1, y1)
        finite(x0); finite(y0); finite(x1); finite(y1)
        lines[#lines + 1] = { x0, y0, x1, y1 }
    end, ...)
    return lines
end

local function closed(lines)
    for i, line in ipairs(lines) do
        local nextLine = lines[i % #lines + 1]
        near(line[3], nextLine[1]); near(line[4], nextLine[2])
    end
end

test("projection: rectangular bounds, uniform scale, north up and roundtrip", function()
    for _, b in ipairs({
        { minX = -8000, maxX = 12000, minY = -2000, maxY = 3000 },
        { minX = 400, maxX = 900, minY = -9000, maxY = 7000 },
    }) do
        for _, size in ipairs({ { 720, 300 }, { 300, 720 } }) do
            for _, zoom in ipairs({ 1, 1.5, 4, 32 }) do
                local v = geometry.view(b, size[1], size[2], zoom)
                near(v.scale, math.min((size[1] - 24) / (b.maxX - b.minX),
                    (size[2] - 24) / (b.maxY - b.minY)) * zoom)
                local x, y = geometry.project(v, v.cx, v.cy)
                near(x, size[1] / 2); near(y, size[2] / 2)
                local east = geometry.project(v, v.cx + 100, v.cy)
                local _, north = geometry.project(v, v.cx, v.cy + 100)
                near(east - x, y - north)
                assert(east > x and north < y)
                for _, point in ipairs({ { b.minX, b.minY }, { b.maxX, b.maxY }, { 37, -91 } }) do
                    local px, py = geometry.project(v, table.unpack(point))
                    local wx, wy = geometry.unproject(v, px, py)
                    near(wx, point[1]); near(wy, point[2])
                    if zoom == 1 and point[1] ~= 37 then
                        assert(px >= 12 - 1e-8 and px <= size[1] - 12 + 1e-8)
                        assert(py >= 12 - 1e-8 and py <= size[2] - 12 + 1e-8)
                    end
                end
            end
        end
    end
    local v = geometry.view({ minX = -1000, maxX = 1000, minY = -500, maxY = 500 }, 720, 300, 3, 0, -83)
    near(v.cx, 0); near(v.cy, -83)
    local wx, wy = geometry.unproject(v, 360, 150)
    near(wx, 0); near(wy, -83)
end)

test("circle segments: radius, continuity, closure and bounded tessellation", function()
    for _, radius in ipairs({ 0, 5, 180, 10000 }) do
        local lines = collect(geometry.circle, 17, -9, radius)
        assert(#lines == math.max(20, math.min(128, math.ceil(radius / 3))))
        closed(lines)
        for _, line in ipairs(lines) do
            near((line[1] - 17)^2 + (line[2] + 9)^2, radius^2, 1e-6)
            near((line[3] - 17)^2 + (line[4] + 9)^2, radius^2, 1e-6)
        end
    end
end)

test("projection clamps panning while retaining the fitted centre on a short axis", function()
    local b = { minX = -8000, maxX = 8000, minY = -2000, maxY = 2000 }
    local fitted = geometry.view(b, 720, 300, 1, 1e9, -1e9)
    near(fitted.cx, 0); near(fitted.cy, 0)
    for _, sign in ipairs({ -1, 1 }) do
        local v = geometry.view(b, 720, 300, 4, sign * 1e9, sign * 1e9)
        near(v.cx, sign * (8000 - 720 / (2 * v.scale)))
        near(v.cy, sign * (2000 - 300 / (2 * v.scale)))
        local wx, wy = geometry.unproject(v, geometry.project(v, v.cx, v.cy))
        near(wx, v.cx); near(wy, v.cy)
    end
end)

test("markers: square NRA, triangle NRO, circular antenna and town cross", function()
    for _, spec in ipairs({ { "NRA", 4 }, { "NRO", 3 }, { "ANTENNA", 20 }, { "TOWN", 2 } }) do
        local lines = collect(geometry.marker, spec[1], 40, 70, 5)
        assert(#lines == spec[2])
        if spec[1] ~= "TOWN" then closed(lines) end
        for _, line in ipairs(lines) do
            for i = 1, 3, 2 do
                assert(line[i] >= 35 and line[i] <= 45 and line[i + 1] >= 65 and line[i + 1] <= 75)
            end
            if spec[1] == "NRA" then
                near(math.abs(line[3] - line[1]) + math.abs(line[4] - line[2]), 10)
            end
        end
        if spec[1] == "NRO" then near(lines[1][1], 40); near(lines[1][2], 65) end
        if spec[1] == "TOWN" then
            near(lines[1][2], 70); near(lines[1][4], 70)
            near(lines[2][1], 40); near(lines[2][3], 40)
        end
    end
end)

test("clip: crossing with both endpoints outside, tangent, reverse and degenerate", function()
    local cases = {
        { { -10, 25, 110, 25 }, { 0, 25, 100, 25 } },
        { { 50, -10, 50, 60 }, { 50, 0, 50, 50 } },
        { { -10, -10, 60, 60 }, { 0, 0, 50, 50 } },
        { { -10, 10, 10, -10 }, { 0, 0, 0, 0 } },
        { { -10, 0, 110, 0 }, { 0, 0, 100, 0 } },
        { { 0, 50, 100, 50 }, { 0, 50, 100, 50 } },
        { { 25, 25, 25, 25 }, { 25, 25, 25, 25 } },
        { { -10, -1, 110, -1 } }, { { -10, 0, -10, 50 } },
        { { -1, -1, -1, -1 } }, { { 101, 0, 101, 50 } },
    }
    for _, case in ipairs(cases) do
        local a = case[1]
        local clipped = { geometry.clip(a[1], a[2], a[3], a[4], 100, 50) }
        if case[2] then
            assert(#clipped == 4)
            for i = 1, 4 do near(clipped[i], case[2][i]) end
            local reverse = { geometry.clip(a[3], a[4], a[1], a[2], 100, 50) }
            near(reverse[1], clipped[3]); near(reverse[2], clipped[4])
            near(reverse[3], clipped[1]); near(reverse[4], clipped[2])
        else
            assert(#clipped == 0, "outside segment was retained")
        end
    end
end)

test("hit testing uses a fixed pixel tolerance at every zoom and nearest item", function()
    local b = { minX = -1000, maxX = 1000, minY = -500, maxY = 500 }
    local item = { id = 1, x = 30, y = -20 }
    for _, zoom in ipairs({ 1, 4, 32 }) do
        local v = geometry.view(b, 720, 300, zoom, item.x, item.y)
        local x, y = geometry.project(v, item.x, item.y)
        assert(geometry.hitTest({ item }, v, x + 10, y, 10) == item)
        assert(geometry.hitTest({ item }, v, x + 10.01, y, 10) == nil)
        assert(geometry.hitTest({}, v, x, y, 10) == nil)
        local other = { id = 2, x = item.x + 5 / v.scale, y = item.y }
        assert(geometry.hitTest({ item, other }, v, x + 4, y, 10) == other)
    end
end)

local function fakeApi(options)
    options = options or {}
    local f = { objects = {}, ids = {}, buttons = {}, checks = {}, logs = {}, violations = {},
        stats = { writes = 0, linesCreated = 0, linesAdded = 0, clears = 0,
            destroyed = 0, terrainReads = 0, samples = 0, scans = 0, edgeReads = 0 },
        mouse = { x = 0, y = 0 }, rect = { x = 137, y = 89, w = 1080, h = 450 }, now = 1000,
        focused = {}, missing = {}, options = options }
    local function check(condition, message)
        if not condition then
            f.violations[#f.violations + 1] = message
            error(message, 2)
        end
    end
    local function tagged(value, name)
        check(type(value) == "table" and value.tag == name, "expected " .. name)
    end
    local function vector(name, fields)
        return { new = function(...)
            check(select("#", ...) == #fields, name .. " constructor arity")
            local result, args = { tag = name }, { ... }
            for i, field in ipairs(fields) do finite(args[i]); result[field] = args[i] end
            return result
        end }
    end
    local common, boxMethods, absoluteMethods = {}, {}, {}
    local methods = {
        Component = {}, TextView = {}, Button = {}, CheckBox = {}, ComboBox = {},
        ScrollArea = {}, Window = {}, LineRenderView = {},
    }
    for _, class in pairs(methods) do setmetatable(class, { __index = common }) end
    local function object(kind, class)
        local o = setmetatable({ kind = kind, serial = #f.objects + 1, destroyed = false,
            enabled = true, visible = true }, { __index = class })
        f.objects[#f.objects + 1] = o
        return o
    end
    local function write(o)
        check(not o.destroyed, "operation on destroyed component")
        f.stats.writes = f.stats.writes + 1
    end
    local function attach(layout, child)
        check(type(child) == "table" and child.serial and not child.destroyed, "expected live GUI item")
        check(not child.parent, "component already attached")
        write(layout)
        child.parent = layout
        layout.items[#layout.items + 1] = child
    end
    function boxMethods:addItem(child) attach(self, child) end
    function absoluteMethods:addItem(child, rect)
        tagged(rect, "Rect")
        attach(self, child)
        child.placement = rect
    end
    function absoluteMethods:getIndex(child)
        for i, item in ipairs(self.items) do if item == child then return i - 1 end end
        return -1
    end
    function absoluteMethods:removeItem(child)
        check(type(child) == "table" and child.serial and not child.destroyed,
            "ILayout.removeItem expects a live layout item, not an index")
        check(child.parent == self, "item is not owned by this layout")
        local index = self:getIndex(child)
        if options.removeErrorAt and f.stats.destroyed == options.removeErrorAt then
            options.removeErrorAt = nil
            error("injected remove failure")
        end
        write(self)
        local item = table.remove(self.items, index + 1)
        item.parent = nil
        return item
    end
    function common:setId(id)
        check(type(id) == "string" and not f.ids[id], "duplicate or invalid component id")
        write(self); self.id = id; f.ids[id] = self
    end
    function common:setName(name)
        check(type(name) == "string", "style name must be a string")
        write(self); self.name = name
    end
    function common:setMinimumSize(size) tagged(size, "Size"); write(self); self.minimumSize = size end
    function common:setMaximumSize(size) tagged(size, "Size"); write(self); self.maximumSize = size end
    function common:setTooltip(text)
        check(type(text) == "string", "tooltip must be a string")
        write(self); self.tooltip = text
    end
    function common:setMouseListener(callback)
        check(type(callback) == "function", "mouse listener must be callable")
        write(self); self.mouseListener = callback
    end
    function common:setEnabled(on)
        check(type(on) == "boolean", "enabled must be boolean")
        write(self); self.enabled = on
    end
    function common:destroy()
        check(not self.parent, "detach item before destroying it")
        write(self); self.destroyed = true; f.stats.destroyed = f.stats.destroyed + 1
    end
    function methods.Component:setLayout(layout)
        check(layout.kind == "AbsoluteLayout" or layout.kind == "BoxLayout", "expected layout")
        write(self); self.layout = layout
    end
    function methods.Component:getLayout() return self.layout end
    function methods.Component:getContentRect() return f.rect end
    function methods.TextView:setText(text)
        check(type(text) == "string", "TextView.setText expects string")
        write(self); self.text = text
    end
    function methods.TextView:setSelectable(on)
        check(type(on) == "boolean", "selectable must be boolean")
        write(self); self.selectable = on
    end
    function methods.Button:onClick(callback)
        check(type(callback) == "function", "button callback must be callable")
        write(self); self.callback = callback
    end
    function methods.CheckBox:setSelected(on, notify)
        check(type(on) == "boolean" and (notify == nil or type(notify) == "boolean"), "checkbox arguments")
        write(self); self.selected = on
        if notify ~= false and self.callback then self.callback(on) end
    end
    function methods.CheckBox:onToggle(callback)
        check(type(callback) == "function", "toggle callback must be callable")
        write(self); self.callback = callback
    end
    function methods.ComboBox:onIndexChanged(callback)
        check(type(callback) == "function", "combo callback must be callable")
        write(self); self.callback = callback
    end
    function methods.ComboBox:clear(emit)
        check(type(emit) == "boolean", "ComboBox.clear requires an emit boolean")
        if options.clearError then error("injected clear failure") end
        write(self); self.items = {}; self.index = -1; self.rebuilds = self.rebuilds + 1
        if emit and self.callback then self.callback(-1) end
    end
    function methods.ComboBox:addItem(text)
        check(type(text) == "string", "ComboBox.addItem expects string")
        if options.addErrorAt and #self.items == options.addErrorAt then error("injected add failure") end
        write(self); self.items[#self.items + 1] = text
        if self.index == -1 then
            self.index = 0
            if self.callback then self.callback(0) end
        end
    end
    function methods.ComboBox:getCurrentIndex() return self.index end
    function methods.ComboBox:getNumItems() return #self.items end
    -- Current integration contract; the older web reference omits this setter.
    -- A native TF2 smoke test is still needed to validate the binding itself.
    function methods.ComboBox:setSelected(index, emit)
        check(math.type(index) == "integer" and index >= 0 and index < #self.items, "invalid combo index")
        check(type(emit) == "boolean", "combo emit must be boolean")
        local changed = self.index ~= index
        write(self); self.index = index
        if changed and emit and self.callback then self.callback(index) end
    end
    function common:onVisibilityChange(callback)
        check(type(callback) == "function", "visibility callback must be callable")
        write(self); self.visibilityCallback = callback
    end
    function methods.Window:addHideOnCloseHandler() write(self); self.hideOnClose = true end
    function methods.Window:setMovable(on)
        check(type(on) == "boolean", "movable must be boolean")
        write(self); self.movable = on
    end
    function methods.Window:setResizable(on)
        check(type(on) == "boolean", "resizable must be boolean")
        write(self); self.resizable = on
    end
    function methods.Window:setVisible(on, emitSignal)
        check(type(on) == "boolean" and type(emitSignal) == "boolean", "visibility arguments")
        local changed = self.visible ~= on
        write(self); self.visible = on
        if changed and emitSignal and self.visibilityCallback then self.visibilityCallback(on) end
    end
    function methods.Window:isVisible() return self.visible end
    function methods.LineRenderView:setColor(color)
        tagged(color, "Vec4f"); write(self); self.color = color
    end
    function methods.LineRenderView:setWidth(width)
        finite(width); check(width > 0, "line width must be positive")
        write(self); self.width = width
    end
    function methods.LineRenderView:addLine(a, b)
        tagged(a, "Vec2f"); tagged(b, "Vec2f")
        check(self.color and self.width, "setColor/setWidth before drawing")
        local rect = self.placement or self.minimumSize
        check(rect ~= nil, "line renderer needs local bounds")
        for _, p in ipairs({ a, b }) do
            check(p.x >= -1e-7 and p.y >= -1e-7 and p.x <= rect.w + 1e-7 and p.y <= rect.h + 1e-7,
                "line coordinates must be local and clipped")
        end
        write(self); self.lines[#self.lines + 1] = { a.x, a.y, b.x, b.y }
        f.stats.linesAdded = f.stats.linesAdded + 1
    end
    function methods.LineRenderView:clear()
        write(self); self.lines = {}; f.stats.clears = f.stats.clears + 1
    end
    local gui = { comp = {}, layout = {}, util = {} }
    gui.layout.BoxLayout = { new = function(direction)
        check(direction == "VERTICAL" or direction == "HORIZONTAL", "invalid box direction")
        local o = object("BoxLayout", boxMethods); o.items = {}; return o
    end }
    gui.layout.AbsoluteLayout = { new = function(...)
        check(select("#", ...) == 0, "AbsoluteLayout.new expects no arguments")
        local o = object("AbsoluteLayout", absoluteMethods); o.items = {}; return o
    end }
    gui.comp.Component = { new = function(name)
        check(type(name) == "string", "Component.new expects style name")
        local o = object("Component", methods.Component); o.name = name; return o
    end }
    gui.comp.TextView = { new = function(text)
        local o = object("TextView", methods.TextView); o:setText(text); return o
    end }
    gui.comp.Button = { new = function(label, toggle)
        check(label.kind == "TextView" and type(toggle) == "boolean", "Button.new arguments")
        local o = object("Button", methods.Button); o.label = label; f.buttons[label.text] = o; return o
    end }
    gui.comp.CheckBox = { new = function(text)
        check(type(text) == "string", "CheckBox.new expects text")
        local o = object("CheckBox", methods.CheckBox); o.text = text; f.checks[text] = o; return o
    end }
    gui.comp.ComboBox = { new = function()
        local o = object("ComboBox", methods.ComboBox)
        o.items, o.index, o.rebuilds = {}, -1, 0; f.dropdown = o; return o
    end }
    gui.comp.ScrollArea = { new = function(child, name)
        check(child.kind == "TextView", "expected details content")
        check(type(name) == "string", "ScrollArea.new requires a component name as its second argument")
        local o = object("ScrollArea", methods.ScrollArea)
        o.child, o.name = child, name
        f.details = child
        return o
    end }
    gui.comp.Window = { new = function(title, layout)
        check(type(title) == "string" and layout.kind == "BoxLayout", "Window.new arguments")
        local o = object("Window", methods.Window); o.layout = layout; f.window = o; return o
    end }
    gui.comp.LineRenderView = { new = function(...)
        check(select("#", ...) == 0, "LineRenderView.new expects no arguments")
        local o = object("LineRenderView", methods.LineRenderView); o.lines = {}
        f.stats.linesCreated = f.stats.linesCreated + 1; return o
    end }
    gui.util.Size = vector("Size", { "w", "h" })
    gui.util.Rect = vector("Rect", { "x", "y", "w", "h" })
    gui.util.getById = function(id)
        check(type(id) == "string", "getById expects string")
        return f.ids[id]
    end
    gui.util.getMouseScreenPos = function() return f.mouse end
    local camera = { focus = function(_, id, flag)
        check(type(id) == "number", "focus expects an entity id")
        check(type(flag) == "boolean", "focus requires a boolean as its second argument")
        if options.cameraError then error("injected camera failure") end
        f.focused[#f.focused + 1] = id
    end }
    local renderer = { getCameraController = function() return camera end }
    local gameUI = { getMainRendererComponent = function() return renderer end }
    gui.util.getGameUI = function() return gameUI end
    if not options.noGameInfo then
        local info = gui.comp.Component.new("GameInfo")
        info:setLayout(gui.layout.BoxLayout.new("HORIZONTAL")); info:setId("gameInfo")
    end
    local types = { TERRAIN = 1, BASE_EDGE = 2, BASE_NODE = 3, BASE_EDGE_TRACK = 4 }
    local vertices = { [1001] = { position = { x = -100, y = 0 } },
        [1002] = { position = { x = 100, y = 80 } } }
    local edge = { node0 = 1001, node1 = 1002,
        tangent0 = { x = 200, y = 200 }, tangent1 = { x = 200, y = -100 } }
    local engine = {
        util = { getWorld = function() return 99 end },
        terrain = { getHeightAt = function(pos)
            tagged(pos, "Vec2f"); f.stats.samples = f.stats.samples + 1
            if options.heightError and f.stats.samples >= options.heightError then error("injected height failure") end
            if options.height then return options.height(pos) end
            return -5
        end },
        entityExists = function(id)
            check(type(id) == "number", "entityExists expects numeric id")
            return not f.missing[id]
        end,
        forEachEntityWithComponent = function(callback, component)
            check(type(callback) == "function" and component == types.BASE_EDGE, "edge enumeration signature")
            f.stats.scans = f.stats.scans + 1
            if options.scanError then error("injected enumeration failure") end
            for _, id in ipairs(options.edges or { 501, 502 }) do callback(id) end
        end,
        getComponent = function(id, component)
            if id == 99 and component == types.TERRAIN then
                f.stats.terrainReads = f.stats.terrainReads + 1
                if options.terrainError then error("injected terrain failure") end
                return { waterLevel = 0 }
            elseif component == types.BASE_EDGE then
                check(id >= 501 and id <= 900, "unexpected edge id")
                f.stats.edgeReads = f.stats.edgeReads + 1
                if options.edgeError then error("injected edge failure") end
                return edge
            elseif component == types.BASE_NODE then
                check(vertices[id] ~= nil, "unexpected node id")
                return vertices[id]
            elseif component == types.BASE_EDGE_TRACK then
                check(id >= 501 and id <= 900, "unexpected track id")
                if id % 2 == 0 then return {} end
                return nil
            end
            check(false, "unexpected engine component read")
        end,
    }
    if options.aliasing then
        local original, shared = engine.getComponent, {}
        engine.getComponent = function(id, component)
            local result = original(id, component)
            for key in pairs(shared) do shared[key] = nil end
            if not result then return nil end
            for key, value in pairs(result) do shared[key] = value end
            return shared
        end
    end
    f.api = { gui = gui, engine = engine, type = { ComponentType = types,
        Vec2f = vector("Vec2f", { "x", "y" }), Vec4f = vector("Vec4f", { "x", "y", "z", "w" }) } }
    function f:click(text)
        local button = assert(self.buttons[text], "unknown button " .. text)
        assert(button.enabled and button.callback, "button disabled or unwired")
        button.callback()
    end
    function f:toggle(text, on)
        assert(self.checks[text], "unknown checkbox " .. text):setSelected(on, true)
    end
    function f:choose(text)
        for i, label in ipairs(self.dropdown.items) do
            if label:find(text, 1, true) then
                -- Inject a user selection, not an invented native ComboBox setter.
                self.dropdown.index = i - 1
                assert(self.dropdown.callback)(i - 1)
                return
            end
        end
        error("dropdown choice not found: " .. text)
    end
    function f:mouseEvent(eventType, x, y, target)
        self.mouse = { x = self.rect.x + x * self.rect.w / 720,
            y = self.rect.y + y * self.rect.h / 300 }
        return assert((target or self.ids.telecom_map_canvas).mouseListener)({ type = eventType, button = 0 })
    end
    function f:close()
        assert(self.window.hideOnClose)
        self.window:setVisible(false, true)
    end
    return f
end

local function withApi(options, fn)
    local oldApi, oldTranslate, oldPrint, oldGame = _G.api, _G._, _G.print, _G.game
    local oldTime = os.time
    local f = fakeApi(options)
    _G.api, _G.game = f.api, nil
    _G._ = function(text) assert(type(text) == "string"); return text end
    _G.print = function(message) f.logs[#f.logs + 1] = tostring(message) end
    os.time = function() return f.now end
    local ok, err = xpcall(function() fn(f) end, debug.traceback)
    _G.api, _G._, _G.print, _G.game = oldApi, oldTranslate, oldPrint, oldGame
    os.time = oldTime
    assert(#f.violations == 0, "strict API violation: " .. table.concat(f.violations, "; "))
    assert(ok, err)
end

test("mock rejects unsupported signatures and enforces layout item ownership", function()
    local f = fakeApi()
    local gui = f.api.gui
    local layout = gui.layout.AbsoluteLayout.new()
    local child = gui.comp.Component.new("Test")
    local function rejects(fn)
        assert(not pcall(fn), "invalid native API call was accepted by the mock")
        f.violations = {}
    end
    rejects(function() gui.layout.AbsoluteLayout.new(720, 300) end)
    rejects(function() layout:addItem(child, 0, 0) end)
    layout:addItem(child, gui.util.Rect.new(0, 0, 720, 300))
    assert(layout:getIndex(child) == 0)
    rejects(function() layout:removeItem(0) end)
    rejects(function() layout:removeItem(1) end)
    rejects(function() child:destroy() end)
    assert(layout:removeItem(child) == child and layout:getIndex(child) == -1)
    child:destroy(); assert(child.destroyed)
    local line = gui.comp.LineRenderView.new()
    assert(line.addPoint == nil and line.setLineWidth == nil)
    rejects(function() line:setColor({ 1, 0, 0, 1 }) end)
    rejects(function() line:setWidth("2") end)
    line:setColor(f.api.type.Vec4f.new(1, 0, 0, 1)); line:setWidth(2)
    line:setMinimumSize(gui.util.Size.new(16, 16))
    rejects(function() line:addLine(0, 0, 10, 10) end)
    rejects(function() line:addLine(f.api.type.Vec2f.new(-1, 0), f.api.type.Vec2f.new(5, 5)) end)
    line:addLine(f.api.type.Vec2f.new(0, 0), f.api.type.Vec2f.new(16, 16))
    assert(#line.lines == 1); line:clear(); assert(#line.lines == 0)
end)

test("ScrollArea constructor requires content and a component name", function()
    local f = fakeApi()
    local gui = f.api.gui
    local content = gui.comp.TextView.new("Details")
    assert(not pcall(gui.comp.ScrollArea.new, content), "missing component name must be rejected")
    assert(not pcall(gui.comp.ScrollArea.new, content, 123), "numeric component name must be rejected")
    local scroll = gui.comp.ScrollArea.new(content, "telecom_map_details")
    assert(scroll.child == content and scroll.name == "telecom_map_details")
end)

test("ComboBox clear requires an explicit boolean and can suppress its callback", function()
    local f = fakeApi()
    local combo = f.api.gui.comp.ComboBox.new()
    combo:addItem("Placeholder")
    assert(not pcall(function() combo:clear() end), "missing emit flag must be rejected")
    assert(not pcall(function() combo:clear(0) end), "numeric emit flag must be rejected")
    local events = 0
    combo:onIndexChanged(function() events = events + 1 end)
    combo:clear(false)
    assert(combo:getNumItems() == 0 and events == 0)
    combo:addItem("Placeholder")
    events = 0
    combo:clear(true)
    assert(combo:getNumItems() == 0 and events == 1)
end)

test("camera focus requires an entity and an explicit boolean", function()
    local f = fakeApi()
    local camera = f.api.gui.util.getGameUI():getMainRendererComponent():getCameraController()
    assert(not pcall(function() camera:focus(1) end), "missing focus flag must be rejected")
    assert(not pcall(function() camera:focus(1, 0) end), "numeric focus flag must be rejected")
    camera:focus(1, true)
    assert(#f.focused == 1 and f.focused[1] == 1)
end)

local function snapshot(revision, change)
    local input = { year = 2023, terrainSize = { x = 64, y = 32 }, nodes = {
        { id = 1, kind = "NRA", name = "Copper", x = -4000, y = 0 },
        { id = 2, kind = "NRO", name = "Fiber", x = 0, y = 1000 },
        { id = 3, kind = "ANTENNA", name = "Radio", x = 4000, y = -1000,
            params = { tech_2g = 1, tech_5g = 1 } },
        { id = 4, kind = "ANTENNA", name = "Offline", x = -6000, y = -2500, params = {} },
    }, towns = { { id = 11, name = "West", x = -3800, y = 300 },
        { id = 12, name = "East", x = 4500, y = -900 } } }
    if change then change(input) end
    return network.computeSnapshot(input, revision or 1)
end

local function nodesSnapshot(revision, change)
    return snapshot(revision, function(input)
        input.towns = {}
        if change then change(input) end
    end)
end

local function open(f)
    f.refreshes = 0
    local ui = map.new(function() f.refreshes = f.refreshes + 1 end)
    assert(ui.window == f.window)
    f.summary = f.window.layout.items[1]
    for i, item in ipairs(f.window.layout.items) do
        if item == f.ids.telecom_map_canvas then
            f.status = f.window.layout.items[i + 1]
            f.exportText = f.window.layout.items[i - 1]
        end
    end
    assert(f.status)
    if not f.window:isVisible() then f:click("Telecom") end
    return ui
end

local function settle(ui, state)
    for _ = 1, 100 do ui:update(state) end
end

local function plane(f, index)
    return f.ids.telecom_map_canvas.layout.items[index].layout
end

local function lineCount(f, index, color)
    local count = 0
    for _, item in ipairs(plane(f, index).items) do
        if item.kind == "LineRenderView" and (not color or
            (item.color.x == color[1] and item.color.y == color[2] and item.color.z == color[3])) then
            count = count + #item.lines
        end
    end
    return count
end

local function drawing(f)
    local parts = {}
    for index = 1, 3 do
        for _, renderer in ipairs(plane(f, index).items) do
            for _, line in ipairs(renderer.lines) do
                parts[#parts + 1] = string.format("%d:%.3f:%.3f:%.3f:%.3f:%.2f:%.6f:%.6f:%.6f:%.6f",
                    index, renderer.color.x, renderer.color.y, renderer.color.z, renderer.color.w,
                    renderer.width, table.unpack(line))
            end
        end
    end
    table.sort(parts)
    return table.concat(parts, "\n")
end

local function runJob(job, f)
    for _ = 1, 100 do
        if job.done then return end
        local samples, edges = f.stats.samples, f.stats.edgeReads
        local done = job:step()
        assert(f.stats.samples - samples <= 128, "terrain work exceeds frame budget")
        assert(f.stats.edgeReads - edges <= 128, "edge work exceeds frame budget")
        if job.done then assert(done == true) end
    end
    error("background job did not finish")
end

test("background: incremental water grid and curved road/rail extraction", function()
    withApi({}, function(f)
        local b = { minX = -200, maxX = 200, minY = -100, maxY = 100 }
        local job = background.new(b)
        assert(not job.done and f.stats.samples == 0 and f.stats.scans == 0)
        job:step()
        assert(f.stats.samples == 128 and not job.done)
        runJob(job, f)
        assert(f.stats.samples == 96 * 48 and #job.terrain == f.stats.samples)
        assert(f.stats.scans == 1 and #job.roads == 4 and #job.rails == 4 and #job.warnings == 0)
        for _, line in ipairs(job.terrain) do
            assert(line[5] == "water")
            assert(line[1] >= b.minX and line[3] <= b.maxX + 1e-8)
            assert(line[2] >= b.minY and line[4] <= b.maxY)
        end
        for _, lines in ipairs({ job.roads, job.rails }) do
            near(lines[1][1], -100); near(lines[1][2], 0)
            near(lines[4][3], 100); near(lines[4][4], 80)
            for i = 1, 3 do near(lines[i][3], lines[i + 1][1]); near(lines[i][4], lines[i + 1][2]) end
            assert(math.abs(lines[1][4] - 20) > 1, "curved edge flattened into a straight chord")
        end
        local samples, edges = f.stats.samples, f.stats.edgeReads
        assert(job:step() == false and job:step() == false)
        assert(f.stats.samples == samples and f.stats.edgeReads == edges and f.stats.scans == 1)
    end)
end)

test("background: land bands, finite segments and edge frame budget", function()
    local ids = {}; for id = 501, 800 do ids[#ids + 1] = id end
    withApi({ edges = ids, height = function(p)
        return p.x < -50 and 30 or p.x < 50 and 120 or 250
    end }, function(f)
        local job = background.new({ minX = -200, maxX = 200, minY = -100, maxY = 100 })
        runJob(job, f)
        assert(#job.roads == 600 and #job.rails == 600)
        local bands = {}
        for _, line in ipairs(job.terrain) do
            bands[line[5]] = true
            for i = 1, 4 do finite(line[i]) end
        end
        assert(bands.hill and bands.high and not bands.water)
    end)
end)

test("background copies engine userdata before subsequent lookups reuse it", function()
    withApi({ aliasing = true }, function(f)
        local job = background.new({ minX = -200, maxX = 200, minY = -100, maxY = 100 })
        runJob(job, f)
        assert(#job.warnings == 0 and #job.roads == 4 and #job.rails == 4)
        near(job.roads[1][1], -100); near(job.roads[4][3], 100)
        near(job.rails[1][2], 0); near(job.rails[4][4], 80)
    end)
end)

test("background spatial index returns visible candidates without duplicates", function()
    withApi({}, function(f)
        local job = background.new({ minX = -200, maxX = 200, minY = -100, maxY = 100 })
        runJob(job, f)
        for _, kind in ipairs({ "roads", "rails" }) do
            local seen, count = {}, 0
            for segment in job:segments(kind, -200, -100, 200, 100) do
                assert(not seen[segment], "segment returned twice at a cell boundary")
                seen[segment], count = true, count + 1
            end
            assert(count == #job[kind])
            assert(job:segments(kind, 1000, 1000, 1100, 1100)() == nil)
        end
    end)
end)

for _, failure in ipairs({ "terrainError", "heightError", "scanError", "edgeError" }) do
    test("background degrades and terminates after " .. failure, function()
        withApi({ [failure] = failure == "heightError" and 4 or true }, function(f)
            local job = background.new({ minX = -200, maxX = 200, minY = -100, maxY = 100 })
            runJob(job, f)
            assert(#job.warnings == 1 and #f.logs == 1)
            contains(job.warnings[1], "injected")
            if failure == "terrainError" or failure == "heightError" then
                assert(#job.roads == 4 and #job.rails == 4, "terrain failure must preserve transport context")
            else
                assert(#job.terrain > 0, "transport failure must preserve terrain context")
            end
            local samples, scans, edges = f.stats.samples, f.stats.scans, f.stats.edgeReads
            for _ = 1, 3 do assert(job:step() == false) end
            assert(#f.logs == 1 and f.stats.samples == samples and f.stats.scans == scans and f.stats.edgeReads == edges)
        end)
    end)
end

test("background ignores deleted edges and missing endpoint entities", function()
    withApi({}, function(f)
        f.missing[501], f.missing[1001] = true, true
        local job = background.new({ minX = -200, maxX = 200, minY = -100, maxY = 100 })
        runJob(job, f)
        assert(#job.roads == 0 and #job.rails == 0 and #job.warnings == 0)
    end)
end)

test("strict GUI construction, style names and real computed snapshot", function()
    withApi({}, function(f)
        local ui, state = open(f), snapshot()
        assert(f.refreshes == 1 and f.window.hideOnClose and not f.window.resizable and f.window.movable)
        assert(f.ids.telecom_map_canvas.name == "TelecomMap")
        assert(#f.ids.telecom_map_canvas.layout.items == 4)
        assert(f.api.gui.comp.LineRenderView.new().addPoint == nil)
        settle(ui, state)
        contains(f.summary.text, "Annee 2023 | NRA 1 | NRO 1 | Antennes 2")
        contains(f.summary.text, "Villes couvertes : 2 / 2")
        assert(#f.dropdown.items == 1 + #state.nodes + #state.towns)
        assert(lineCount(f, 1) > 4 and lineCount(f, 2) > 0 and lineCount(f, 3) > 0)
        assert(not f.buttons["Voir en jeu"].enabled and not f.buttons["Centrer carte"].enabled)
        assert(#f.logs == 0)
        for _, item in ipairs(plane(f, 4).items) do assert(item.name == "TelecomMapLabel") end
    end)
end)

test("failed initial dropdown clear is retried at the same revision without selecting an empty list", function()
    withApi({ clearError = true }, function(f)
        local ui, state = open(f), snapshot()
        for attempt = 1, 2 do
            local ok, err = pcall(function() ui:update(state) end)
            assert(not ok); contains(err, "injected clear failure")
            assert(f.dropdown:getNumItems() == 0 and not f.dropdown.enabled)
            assert(f.dropdown.index == -1)
        end
        f.options.clearError = nil
        ui:update(state)
        assert(f.dropdown.enabled and f.dropdown:getNumItems() == 7 and f.dropdown.index == 0)
        f:choose("Copper (#1)"); ui:update(state)
        contains(f.details.text, "Copper  (#1)")
    end)
end)

test("partial dropdown rebuild resets its callback guard and preserves selection on retry", function()
    withApi({}, function(f)
        local ui, state = open(f), snapshot()
        ui:update(state)
        f:choose("Copper (#1)"); ui:update(state)
        state = snapshot(2, function(input) input.nodes[1].name = "Renamed" end)
        f.options.addErrorAt = 2
        local ok, err = pcall(function() ui:update(state) end)
        assert(not ok); contains(err, "injected add failure")
        assert(f.dropdown:getNumItems() == 2 and not f.dropdown.enabled)
        f.dropdown.callback(0)
        f.options.addErrorAt = nil
        ui:update(state)
        contains(f.details.text, "Renamed  (#1)")
        assert(f.dropdown.enabled and f.dropdown:getNumItems() == 7)
        f:choose("East (#12)"); ui:update(state)
        contains(f.details.text, "East  (#12)")
    end)
end)

test("selection never reaches the native setter with an empty item list", function()
    withApi({}, function(f)
        local ui, state = open(f), snapshot()
        ui:update(state)
        f:choose("East (#12)"); ui:update(state)
        f.dropdown:clear(false)
        ui.dirty = true
        ui:update(state)
        assert(f.dropdown.index == -1)
        ui:update(snapshot(2))
        assert(f.dropdown:getNumItems() == 7)
        contains(f.dropdown.items[f.dropdown.index + 1], "East (#12)")
    end)
end)

test("failed label cleanup retries without removing already destroyed components", function()
    withApi({}, function(f)
        local ui, state = open(f), snapshot()
        ui:update(state)
        f.options.removeErrorAt = f.stats.destroyed + 1
        ui.dirty = true
        local ok, err = pcall(function() ui:update(state) end)
        assert(not ok); contains(err, "injected remove failure")
        assert(ui.dirty)
        ui:update(state)
        assert(not ui.dirty and #plane(f, 4).items > 0)
    end)
end)

test("empty computed snapshot displays known zeroes without a style loader", function()
    withApi({}, function(f)
        local ui = open(f)
        local state = network.computeSnapshot({ year = 2023, nodes = {}, towns = {} }, 1)
        settle(ui, state)
        contains(f.summary.text, "Annee 2023 | NRA 0 | NRO 0 | Antennes 0")
        contains(f.summary.text, "Villes couvertes : 0 / 0")
        contains(f.summary.text, "0.0%")
        contains(f.status.text, "Limites estimees")
        assert(#f.dropdown.items == 1 and lineCount(f, 2) == 0)
    end)
end)

test("kind and technology filters remove coverage and markers independently", function()
    withApi({}, function(f)
        local ui, state = open(f), snapshot()
        settle(ui, state)
        local nra, nro, antenna = { 0.25, 0.65, 1 }, { 0.8, 0.5, 1 }, { 1, 0.65, 0.2 }
        for _, spec in ipairs({ { "NRA", nra }, { "NRO", nro }, { "Antennes", antenna } }) do
            assert(lineCount(f, 3, spec[2]) > 0)
            f:toggle(spec[1], false); ui:update(state)
            assert(lineCount(f, 3, spec[2]) == 0)
            f:toggle(spec[1], true); ui:update(state)
            assert(lineCount(f, 3, spec[2]) > 0)
        end
        local techColor = { 1, 0.78, 0.25 }
        assert(lineCount(f, 2, techColor) > 0)
        f:toggle("2G", false); ui:update(state)
        assert(lineCount(f, 2, techColor) == 0 and lineCount(f, 3, antenna) > 0)
        f:toggle("2G", true); ui:update(state)
        assert(lineCount(f, 2, techColor) > 0)
        for _, name in ipairs({ "NRA", "NRO", "Antennes" }) do f:toggle(name, false) end
        ui:update(state); assert(lineCount(f, 2) == 0)
        for _, name in ipairs({ "NRA", "NRO", "Antennes" }) do f:toggle(name, true) end
        ui:update(state); assert(lineCount(f, 2) > 0)
        local labels, markers = #plane(f, 4).items, lineCount(f, 3)
        f:toggle("Noms", false); ui:update(state)
        assert(#plane(f, 4).items == labels - #state.towns and lineCount(f, 3) == markers)
        f:toggle("Villes", false); ui:update(state)
        assert(lineCount(f, 3) == markers - 2 * #state.towns)
    end)
end)

test("context filters, hatching and selected-only coverage are reversible", function()
    withApi({}, function(f)
        local ui, state = open(f), snapshot()
        settle(ui, state)
        local initial = drawing(f)
        for _, name in ipairs({ "Relief / eau", "Routes", "Rails" }) do f:toggle(name, false) end
        ui:update(state); assert(lineCount(f, 1) == 4)
        for _, name in ipairs({ "Relief / eau", "Routes", "Rails" }) do f:toggle(name, true) end
        ui:update(state); assert(drawing(f) == initial)
        local coverage = lineCount(f, 2)
        f:toggle("Hachures", true); ui:update(state); assert(lineCount(f, 2) > coverage)
        f:toggle("Hachures", false); ui:update(state); assert(lineCount(f, 2) == coverage)
        f:toggle("Couverture : selection", true); ui:update(state); assert(lineCount(f, 2) == 0)
        f:choose("Copper (#1)"); ui:update(state)
        assert(lineCount(f, 2) > 0 and lineCount(f, 2) < coverage)
        f:choose("West (#11)"); ui:update(state); assert(lineCount(f, 2) == 0)
        f:toggle("Couverture : selection", false); ui:update(state); assert(lineCount(f, 2) == coverage)
    end)
end)

test("dropdown selection, details, camera and centering", function()
    withApi({}, function(f)
        local ui, state = open(f), snapshot()
        ui:update(state)
        f:choose("Copper (#1)"); ui:update(state)
        contains(f.details.text, "Copper  (#1)"); contains(f.details.text, "NRA : 1500 m | actif")
        contains(f.details.text, "Villes : West")
        f:click("Voir en jeu"); assert(f.focused[1] == 1)
        f:click("Centrer carte"); ui:update(state)
        near(ui.cx, state.nodes[1].x); near(ui.cy, state.nodes[1].y); assert(ui.zoom >= 4)
        f:choose("West (#11)"); ui:update(state)
        contains(f.details.text, "Contributions : fixe 3% | mobile 0%")
        contains(f.details.text, "Copper : NRA")
        f:choose("Offline (#4)"); ui:update(state); contains(f.details.text, "desactive")
        f:choose("Selectionner..."); ui:update(state)
        assert(not f.buttons["Voir en jeu"].enabled and not f.buttons["Centrer carte"].enabled)
        contains(f.details.text, "Selectionnez")
    end)
end)

test("mouse selection uses screen minus content rect and independent W/H scaling", function()
    withApi({}, function(f)
        local ui, state = open(f), snapshot()
        ui:update(state)
        f.rect = { x = 311, y = 127, w = 1440, h = 450 }
        local v = geometry.view(state.bounds, 720, 300, 1)
        local x, y = geometry.project(v, state.nodes[3].x, state.nodes[3].y)
        assert(f:mouseEvent(2, x, y)); ui:update(state); contains(f.details.text, "Radio  (#3)")
        contains(f.dropdown.items[f.dropdown.index + 1], "Radio (#3)")
        f:toggle("Antennes", false); ui:update(state)
        f:mouseEvent(2, x, y); ui:update(state); contains(f.details.text, "Selectionnez")
        f:toggle("Antennes", true); ui:update(state)
        local labelFound = false
        for _, label in ipairs(plane(f, 4).items) do
            if label.text == "West" then
                labelFound = true
                local tx, ty = geometry.project(v, state.towns[1].x, state.towns[1].y)
                assert(f:mouseEvent(2, tx, ty, label)); ui:update(state)
                contains(f.details.text, "West  (#11)")
                break
            end
        end
        assert(labelFound, "town label was not rendered")
        f:click("+"); ui:update(state)
        v = geometry.view(state.bounds, 720, 300, ui.zoom, ui.cx, ui.cy)
        x, y = geometry.project(v, state.nodes[2].x, state.nodes[2].y)
        f:mouseEvent(2, x + 9, y, plane(f, 3).items[1]); ui:update(state)
        contains(f.details.text, "Fiber  (#2)")
        f:mouseEvent(2, x + 11, y); ui:update(state); contains(f.details.text, "Selectionnez")
        f.rect.w = 0; assert(f:mouseEvent(2, 0, 0) == false)
    end)
end)

test("zoom buttons clamp, dragging pans and its trailing click does not select", function()
    withApi({}, function(f)
        local ui, state = open(f), snapshot()
        ui:update(state)
        for _ = 1, 20 do f:click("+"); ui:update(state) end
        near(ui.zoom, 32)
        for _ = 1, 20 do f:click("-"); ui:update(state) end
        near(ui.zoom, 1)
        f:choose("Fiber (#2)"); ui:update(state)
        f:click("+"); ui:update(state)
        local v = geometry.view(state.bounds, 720, 300, ui.zoom, ui.cx, ui.cy)
        assert(f:mouseEvent(0, 350, 140)); assert(f:mouseEvent(5, 380, 160))
        near(ui.cx, v.cx - 30 / v.scale); near(ui.cy, v.cy + 20 / v.scale)
        f:mouseEvent(1, 380, 160); f:mouseEvent(2, 380, 160); ui:update(state)
        contains(f.details.text, "Fiber  (#2)")
        f:click("Carte entiere"); ui:update(state)
        assert(ui.zoom == 1 and ui.cx == nil and ui.cy == nil)
    end)
end)

test("hidden updates do no work, close/reopen preserves controls and resumes jobs", function()
    withApi({}, function(f)
        local refreshes = 0
        local ui = map.new(function() refreshes = refreshes + 1 end)
        assert(not ui.window:isVisible())
        local state, writes, count = nodesSnapshot(), f.stats.writes, #f.objects
        for _ = 1, 5 do ui:update(state) end
        assert(f.stats.writes == writes and #f.objects == count and f.stats.terrainReads == 0)
        f:click("Telecom"); ui:update(state)
        assert(refreshes == 1 and f.stats.samples == 128)
        f:toggle("Noms", false); f:close()
        writes, count = f.stats.writes, #f.objects
        local samples, added = f.stats.samples, f.stats.linesAdded
        state = nodesSnapshot(2, function(input) input.year = 2024 end)
        for _ = 1, 10 do ui:update(state) end
        assert(f.stats.writes == writes and #f.objects == count and f.stats.samples == samples)
        assert(f.stats.linesAdded == added and not ui.showNames)
        f:click("Telecom"); ui:update(state)
        assert(refreshes == 2 and ui.window:isVisible() and not ui.showNames)
        contains(f.window.layout.items[1].text, "Annee 2024")
        assert(f.stats.samples > samples and f.stats.terrainReads == 1)
    end)
end)

test("redraw reuses line pools, clears hidden groups and destroys detached labels", function()
    withApi({}, function(f)
        local ui, state = open(f), snapshot()
        settle(ui, state)
        local initial, created = drawing(f), f.stats.linesCreated
        local labels, destroyed = #plane(f, 4).items, f.stats.destroyed
        for _ = 1, 12 do
            ui.dirty = true; ui:update(state)
            assert(drawing(f) == initial and f.stats.linesCreated == created)
            assert(#plane(f, 4).items == labels)
        end
        assert(f.stats.destroyed == destroyed + 12 * labels)
        local added, clears = f.stats.linesAdded, f.stats.clears
        for _ = 1, 5 do ui:update(state) end
        assert(f.stats.linesAdded == added and f.stats.clears == clears)
        local oldLabel = plane(f, 4).items[1]
        f:toggle("Noms", false); ui:update(state)
        assert(oldLabel.destroyed and not oldLabel.parent)
        f:toggle("Noms", true); ui:update(state)
        assert(drawing(f) == initial and f.stats.linesCreated == created)
    end)
end)

test("dense coverage is chunked into bounded pooled renderers", function()
    withApi({ terrainError = true, edges = {} }, function(f)
        local ui = open(f)
        local state = snapshot(1, function(input)
            input.nodes, input.towns = {}, {}
            for id = 1, 160 do
                input.nodes[id] = { id = id, kind = "ANTENNA", x = 0, y = 0, params = { tech_2g = 1 } }
            end
        end)
        settle(ui, state)
        assert(#plane(f, 2).items > 1 and lineCount(f, 2) > 1500)
        for _, renderer in ipairs(plane(f, 2).items) do assert(#renderer.lines <= 1500) end
        local created, lines = f.stats.linesCreated, lineCount(f, 2)
        ui.dirty = true; ui:update(state)
        assert(f.stats.linesCreated == created and lineCount(f, 2) == lines)
    end)
end)

test("node details are safe without any town or translation-loader dependency", function()
    withApi({}, function(f)
        local ui, state = open(f), nodesSnapshot()
        ui:update(state)
        f:choose("Copper (#1)"); ui:update(state)
        contains(f.details.text, "NRA : 1500 m | actif")
        contains(f.details.text, "Villes : aucune")
    end)
end)

test("coverage budget is capped and disabling a dense group clears every pool chunk", function()
    withApi({ terrainError = true, edges = {} }, function(f)
        local ui = open(f)
        local state = nodesSnapshot(1, function(input)
            input.nodes = {}
            for id = 1, 800 do
                input.nodes[id] = { id = id, kind = "ANTENNA", x = 0, y = 0, params = { tech_2g = 1 } }
            end
        end)
        settle(ui, state)
        assert(ui.limited and lineCount(f, 2) == 16000)
        assert(lineCount(f, 3) <= 6000)
        contains(f.status.text, "Affichage limite")
        for _, renderer in ipairs(plane(f, 2).items) do assert(#renderer.lines <= 1500) end
        f:toggle("Antennes", false); ui:update(state)
        assert(lineCount(f, 2) == 0 and not ui.limited)
        -- The scale bar can allocate its first renderer once markers no longer exhaust the budget.
        local created = f.stats.linesCreated
        f:toggle("Antennes", true); ui:update(state)
        assert(lineCount(f, 2) == 16000 and f.stats.linesCreated == created)
    end)
end)

test("same revision is cached; changed revision updates data, names and selection", function()
    withApi({}, function(f)
        local ui, state = open(f), snapshot()
        settle(ui, state)
        f:choose("Copper (#1)"); ui:update(state)
        local initial, rebuilds, reads = drawing(f), f.dropdown.rebuilds, f.stats.terrainReads
        local copy = snapshot(1)
        ui:update(copy)
        assert(drawing(f) == initial and f.dropdown.rebuilds == rebuilds)
        state = snapshot(2, function(input) input.year = 2024; input.nodes[1].x = -3000 end)
        ui:update(state)
        contains(f.summary.text, "Annee 2024"); contains(f.details.text, "X : -3000 m")
        assert(drawing(f) ~= initial and f.dropdown.rebuilds == rebuilds and f.stats.terrainReads == reads)
        state = snapshot(3, function(input) input.nodes[1].name = "Renamed" end)
        ui:update(state)
        contains(f.details.text, "Renamed  (#1)")
        assert(f.dropdown.rebuilds == rebuilds + 1)
        f:choose("Renamed (#1)"); ui:update(state)
        state = snapshot(4, function(input) table.remove(input.nodes, 1) end)
        ui:update(state)
        assert(not f.buttons["Voir en jeu"].enabled)
        contains(f.details.text, "Selectionnez")
    end)
end)

test("snapshot errors retain stale drawing, including error changes at same revision", function()
    withApi({}, function(f)
        local ui, state = open(f), snapshot()
        settle(ui, state)
        f:choose("Copper (#1)"); ui:update(state)
        local initial, summary, rebuilds = drawing(f), f.summary.text, f.dropdown.rebuilds
        local stale = snapshot(2); stale.error = "scan unavailable"
        ui:update(stale)
        assert(drawing(f) == initial and f.summary.text == summary and f.dropdown.rebuilds == rebuilds)
        contains(f.details.text, "Copper  (#1)"); contains(f.status.tooltip, "scan unavailable")
        local repeated = snapshot(2); repeated.error = "same revision failure"
        local added = f.stats.linesAdded
        ui:update(repeated)
        contains(f.status.tooltip, "same revision failure"); assert(f.stats.linesAdded == added)
        local recovered = snapshot(2)
        ui:update(recovered)
        assert(not f.status.text:find("non actualisees", 1, true) and drawing(f) == initial)
        ui:update(snapshot(3))
        assert(not f.status.text:find("non actualisees", 1, true))
    end)
end)

test("initial unknown snapshot with bounds and no metrics must not crash or invent zeroes", function()
    withApi({}, function(f)
        local ui = open(f)
        local unknown = { revision = 0, nodes = {}, towns = {}, coverage = {},
            bounds = { minX = -128, maxX = 128, minY = -128, maxY = 128 },
            boundsEstimated = true, error = "En attente du premier calcul moteur" }
        ui:update(unknown)
        contains(f.summary.tooltip, unknown.error)
        assert(not f.summary.text:find("Annee", 1, true) and not f.summary.text:find("0.0%", 1, true))
        unknown = { revision = 1, nodes = {}, towns = {}, coverage = {}, bounds = unknown.bounds,
            boundsEstimated = true, error = "first engine scan failed" }
        ui:update(unknown)
        contains(f.summary.tooltip, unknown.error)
        settle(ui, snapshot(2)); contains(f.summary.text, "Annee 2023")
    end)
end)

test("minimal initial unknown snapshot and nil/no-bounds states are safe", function()
    withApi({}, function(f)
        local ui = open(f)
        ui:update(nil); contains(f.summary.text, "Chargement")
        ui:update({ error = "no bounds yet" }); contains(f.summary.tooltip, "no bounds yet")
        ui:update({ revision = 0, bounds = { minX = -128, maxX = 128, minY = -128, maxY = 128 },
            error = "unknown snapshot" })
        contains(f.summary.tooltip, "unknown snapshot")
    end)
end)

test("successful snapshot clears the previous unknown-state error tooltip", function()
    withApi({}, function(f)
        local ui = open(f)
        ui:update({ revision = 0, bounds = { minX = -128, maxX = 128, minY = -128, maxY = 128 },
            error = "initial scan failed" })
        contains(f.summary.tooltip, "initial scan failed")
        ui:update(network.computeSnapshot({ year = 2023, nodes = {}, towns = {} }, 1))
        contains(f.summary.text, "Annee 2023")
        assert(not f.summary.tooltip or not f.summary.tooltip:find("initial scan failed", 1, true),
            "summary still advertises the initial error after a successful snapshot")
    end)
end)

test("background failures degrade visibly; refresh and bounds changes restart jobs", function()
    withApi({ heightError = 4, scanError = true }, function(f)
        local ui, state = open(f), nodesSnapshot()
        settle(ui, state)
        contains(f.status.text, "Fond incomplet")
        assert(lineCount(f, 2) > 0 and lineCount(f, 3) > 0 and #f.logs == 2)
        local reads, samples, scans = f.stats.terrainReads, f.stats.samples, f.stats.scans
        state = nodesSnapshot(2)
        settle(ui, state)
        assert(f.stats.terrainReads == reads and f.stats.samples == samples and f.stats.scans == scans)
        f.options.heightError, f.options.scanError = nil, nil
        f:click("Actualiser"); settle(ui, state)
        assert(f.refreshes == 2 and f.stats.terrainReads == reads + 1)
        assert(not f.status.text:find("Fond incomplet", 1, true) and lineCount(f, 1) > 4)
        state = nodesSnapshot(3, function(input) input.terrainSize = { x = 32, y = 32 } end)
        ui:update(state)
        assert(f.stats.terrainReads == reads + 2)
    end)
end)

test("periodic background refresh retains old drawing and pauses while hidden", function()
    withApi({}, function(f)
        local ui, state = open(f), snapshot()
        settle(ui, state)
        local initial, reads = drawing(f), f.stats.terrainReads
        f.now = f.now + 60
        ui:update(state)
        assert(f.stats.terrainReads == reads + 1 and drawing(f) == initial)
        settle(ui, state)
        assert(drawing(f) == initial)
        f:close()
        f.now = f.now + 60
        ui:update(state)
        assert(f.stats.terrainReads == reads + 1)
        f:click("Telecom"); ui:update(state)
        assert(f.stats.terrainReads == reads + 2)
    end)
end)

test("missing gameInfo opens a usable window; camera failures and deleted selection are safe", function()
    withApi({ noGameInfo = true, cameraError = true }, function(f)
        local ui, state = open(f), snapshot()
        assert(f.window:isVisible())
        ui:update(state)
        f:choose("Copper (#1)"); ui:update(state)
        f:click("Voir en jeu"); contains(f.status.text, "Camera indisponible")
        ui:update(state); contains(f.status.text, "Camera indisponible")
        assert(#f.focused == 0)
        local logs = #f.logs
        f.missing[1] = true; f:click("Voir en jeu")
        assert(#f.logs == logs and #f.focused == 0)
        f:close(); local added = f.stats.linesAdded
        ui:update(state); assert(f.stats.linesAdded == added)
    end)
end)

test("HTML export is explicit, continues while hidden, can cancel and reports failures", function()
    local previous = package.loaded.telecom_export
    local jobs, fail = {}, false
    package.loaded.telecom_export = { new = function(state, options)
        if fail then error("injected export failure") end
        assert(state.year == 2023 and options.terrainResolution == 512)
        local job = { done = false, progress = 0, phase = "Terrain", warnings = {}, steps = 0 }
        function job:step()
            self.steps = self.steps + 1; self.progress = self.steps * 0.3
            if self.steps == 3 then self.done = true; self.path = "/exports/telecom.html" end
        end
        function job:cancel() self.cancelled = true end
        jobs[#jobs + 1] = job
        return job
    end }
    local ok, err = pcall(function()
        withApi({}, function(f)
            local ui, state = open(f), snapshot()
            assert(not f.buttons["Exporter HTML"].enabled)
            ui:update(state); assert(#jobs == 0 and f.buttons["Exporter HTML"].enabled)
            f:click("Exporter HTML"); ui:update(state)
            assert(#jobs == 1 and jobs[1].steps == 1 and f.buttons["Annuler export"].enabled)
            contains(f.exportText.text, "30%")
            f:close(); ui:update(state); ui:update(state)
            assert(jobs[1].done)
            f:click("Telecom"); ui:update(state)
            contains(f.exportText.text, "/exports/telecom.html")
            f:click("Exporter HTML"); ui:update(state)
            jobs[2].warnings = { "Terrain incomplet" }
            f:click("Annuler export"); ui:update(state)
            assert(jobs[2].cancelled and jobs[2].steps == 1)
            assert(f.exportText.text == "Export annule.", "content warning is not a cleanup failure")
            fail = true
            f:click("Exporter HTML"); ui:update(state)
            contains(f.exportText.tooltip, "injected export failure")
            fail = false
            f:click("Exporter HTML")
            jobs[3].done, jobs[3].error = true, "Write failed"
            jobs[3].warnings = { "Cleanup remove /exports/test.part: Permission denied" }
            ui:update(state)
            contains(f.exportText.tooltip, "Write failed")
            contains(f.exportText.tooltip, "/exports/test.part")
            f:click("Exporter HTML"); ui:update(state)
            jobs[4].cleanupError = "Cleanup close failed"
            jobs[4].warnings = { jobs[4].cleanupError }
            f:click("Annuler export"); ui:update(state)
            contains(f.exportText.text, "nettoyage incomplet")
            local stale = snapshot(2); stale.error = "stale"
            ui:update(stale); assert(not f.buttons["Exporter HTML"].enabled)
        end)
    end)
    package.loaded.telecom_export = previous
    assert(ok, err)
end)

print(string.format("%d tests passed; %d failed", passed, failed))
if failed > 0 then os.exit(1) end
