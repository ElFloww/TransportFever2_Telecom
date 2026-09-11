-- Run from the repository root: lua tests/telecom_network_test.lua
package.path = "./res/scripts/?.lua;" .. package.path
local network = require "telecom_network"
local passed = 0
local function test(name, fn)
    fn()
    passed = passed + 1
    print("ok - " .. name)
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 1e-10, tostring(actual) .. " ~= " .. tostring(expected))
end
local function rawNode(id, kind, x, y, params)
    return { id = id, kind = kind, x = x or 0, y = y or 0, z = 20, params = params }
end
local function town(id, x, y)
    return { id = id, name = "Town " .. id, x = x or 0, y = y or 0, z = 200 }
end
local function snapshot(nodes, towns, year)
    return network.computeSnapshot({ nodes = nodes, towns = towns, year = year or 2023 }, 7)
end
local function serializable(value)
    local kind = type(value)
    assert(kind == "table" or kind == "number" or kind == "string" or kind == "boolean")
    if kind == "table" then
        assert(getmetatable(value) == nil)
        for key, child in pairs(value) do serializable(key); serializable(child) end
    elseif kind == "number" then
        assert(value == value and math.abs(value) < math.huge)
    end
end

test("inclusive 2D boundaries, outside and altitude ignored", function()
    local s = snapshot({ rawNode(1, "NRA") }, { town(10, 900, 1200), town(20, 1500.001), town(30, -1500) })
    assert(s.revision == 7 and s.coveredTowns == 2)
    assert(s.coverage[10].hasFixed and not s.coverage[20].hasFixed and s.coverage[30].hasFixed)
    assert(#s.nodes[1].services[1].townIds == 2)
    near(s.globalBonus, 0.02)
end)

test("every mobile year boundary and radius", function()
    for _, tech in ipairs(network.techs) do
        local node = rawNode(1, "ANTENNA", 0, 0, { [tech.key] = 1 })
        local before = snapshot({ node }, { town(10) }, tech.year - 1)
        assert(before.coveredTowns == 0 and #before.nodes == 1)
        local after = snapshot({ node }, { town(10, tech.radius), town(20, tech.radius + 0.01) }, tech.year)
        near(after.globalBonus, tech.bonus / 2)
        assert(after.coveredTowns == 1)
        for _, service in ipairs(after.nodes[1].services) do
            assert(service.active == (service.key == tech.key))
            assert(service.configured == (service.key == tech.key))
        end
    end
end)

test("named parameters only and inactive antenna marker", function()
    local params = { [0] = 1, [1] = 1, [2] = 1, tech_2g = 0, tech_5gp = 1 }
    local s = snapshot({ rawNode(1, "ANTENNA", 0, 0, params) }, { town(10) }, 2022)
    assert(#s.nodes == 1 and #s.nodes[1].services == 7 and s.coveredTowns == 0)
    for _, service in ipairs(s.nodes[1].services) do
        assert(not service.active and #service.townIds == 0)
        assert(service.configured == (service.key == "tech_5gp"))
    end
    local empty = snapshot({ rawNode(1, "ANTENNA") }, { town(10) })
    assert(#empty.nodes == 1 and empty.globalBonus == 0 and empty.interval == 60)
end)

test("fixed service availability", function()
    for kind, year in pairs({ NRA = 1974, NRO = 2007 }) do
        local before = snapshot({ rawNode(1, kind) }, { town(10) }, year - 1)
        assert(before.coveredTowns == 0 and before.nodes[1].services[1].configured)
        assert(snapshot({ rawNode(1, kind) }, { town(10) }, year).coveredTowns == 1)
    end
end)

test("best fixed, summed mobile including overlaps, synergy, all-town average", function()
    local nodes = {
        rawNode(1, "NRA"), rawNode(2, "NRO"), rawNode(3, "NRO"),
        rawNode(4, "ANTENNA", 0, 0, { tech_2g = 1, tech_3g = 1 }),
        rawNode(5, "ANTENNA", 0, 0, { tech_2g = 1 }),
    }
    local s = snapshot(nodes, { town(10), town(20, 10000) })
    local c = s.coverage[10]
    near(c.fixedBonus, 0.08)
    near(c.mobileBonus, 0.07)
    near(c.bonus, 0.18)
    near(s.globalBonus, 0.09)
    assert(s.coveredTowns == 1 and s.interval == 54)
    assert(s.coverage[20].bonus == 0)
end)

test("global cap only, not per-town cap", function()
    local nodes = { rawNode(1, "NRO") }
    local params = {}
    for _, tech in ipairs(network.techs) do params[tech.key] = 1 end
    for id = 2, 4 do nodes[#nodes + 1] = rawNode(id, "ANTENNA", 0, 0, params) end
    local s = snapshot(nodes, { town(10) })
    assert(s.coverage[10].bonus > 0.6)
    near(s.globalBonus, 0.6)
    assert(s.interval == 24)
    local diluted = snapshot(nodes, { town(10), town(20, 10000), town(30, 20000) })
    near(diluted.globalBonus, s.coverage[10].bonus / 3)
end)

test("terrain tile bounds and estimated discs including inactive services", function()
    local input = { year = 2023, nodes = { rawNode(1, "NRO", 10000) }, towns = {}, terrainSize = { x = 64, y = 32 } }
    local s = network.computeSnapshot(input)
    assert(not s.boundsEstimated and s.bounds.minX == -8192 and s.bounds.maxY == 4096)
    local fallback = snapshot({ rawNode(1, "ANTENNA", -1000, 500) }, { town(10, 7000, -8000) })
    assert(fallback.boundsEstimated and fallback.bounds.minX == -3000 and fallback.bounds.maxX == 7000)
    assert(fallback.bounds.minY == -8000 and fallback.bounds.maxY == 2500)
    local point = snapshot({}, { town(10, 42, -17) })
    assert(point.bounds.minX < 42 and point.bounds.maxY > -17)
    local empty = snapshot({}, {})
    assert(empty.globalBonus == 0 and empty.coveredTowns == 0 and empty.interval == 60)
    serializable(empty)
end)

test("fresh deterministic snapshot without input/catalogue mutation", function()
    local nodes = { rawNode(2, "ANTENNA", 0, 0, { tech_2g = 1 }), rawNode(1, "NRA") }
    local towns = { town(20), town(10) }
    local a, b = snapshot(nodes, towns), snapshot(nodes, towns)
    assert(a.nodes[1].id == 1 and a.towns[1].id == 10)
    assert(nodes[1].id == 2 and nodes[1].services == nil and towns[1].id == 20)
    assert(network.techs[1].townIds == nil)
    a.nodes[2].services[1].townIds[1] = -1
    assert(b.nodes[2].services[1].townIds[1] == 10)
    serializable(b)
end)

local function fakeEngine()
    local types = { CONSTRUCTION = 13, TERRAIN = 40, NAME = 63 }
    local con = {
        fileName = "telecom/antenna.con", params = { tech_2g = 1 },
        transf = { col = function(self, index)
            assert(index == 3)
            return { x = 50, y = -80, z = 12 }
        end },
    }
    local fixture = { year = 2023, terrain = { size = { x = 16, y = 8 } }, con = con }
    local fakeApi = {
        type = { ComponentType = types },
        engine = {
            util = { getWorld = function() return 99 end },
            forEachEntityWithComponent = function(callback, component)
                assert(component == types.CONSTRUCTION)
                callback(12)
                callback(13)
            end,
            getComponent = function(id, component)
                if id == 99 and component == types.TERRAIN then return fixture.terrain end
                if id == 12 and component == types.CONSTRUCTION then return fixture.con end
                if id == 13 and component == types.CONSTRUCTION then return { fileName = "other.con" } end
                if id == 12 and component == types.NAME then return { name = "Test antenna" } end
                error("Unexpected component read")
            end,
        },
    }
    local interface = {
        getGameTime = function() return { time = 123456, date = { year = fixture.year } } end,
        getTowns = function()
            if fixture.failTowns then return nil end
            return { 21 }
        end,
        getEntity = function(id)
            assert(id == 21)
            return { name = "Test town", position = fixture.badPosition and {} or { 50, -80, 30 } }
        end,
    }
    return fakeApi, interface, fixture
end

test("documented engine collection, Mat4f, world id, named params, plain snapshot", function()
    local api, interface = fakeEngine()
    local s = network.computeSnapshot(network.collect(api, interface), 10)
    assert(s.year == 2023 and s.revision == 10 and #s.nodes == 1 and #s.towns == 1)
    assert(s.nodes[1].x == 50 and s.nodes[1].y == -80 and s.nodes[1].z == 12)
    assert(s.nodes[1].name == "Test antenna" and s.towns[1].z == 30)
    assert(s.bounds.maxX == 2048 and s.bounds.maxY == 1024 and not s.boundsEstimated)
    near(s.globalBonus, 0.02)
    serializable(s)
end)

test("missing terrain estimates bounds, missing year/position fails explicitly", function()
    local api, interface, fixture = fakeEngine()
    fixture.terrain = nil
    assert(network.computeSnapshot(network.collect(api, interface)).boundsEstimated)
    fixture.year = nil
    local ok, err = pcall(network.collect, api, interface)
    assert(not ok and tostring(err):find("Annee"))
    fixture.year, fixture.badPosition = 2023, true
    ok, err = pcall(network.collect, api, interface)
    assert(not ok and tostring(err):find("Position invalide"))
    fixture.badPosition, fixture.failTowns = false, true
    ok, err = pcall(network.collect, api, interface)
    assert(not ok and tostring(err):find("Liste des villes"))
end)

test("engine lifecycle, real-time throttle, errors retain snapshot, GUI save/load only", function()
    local oldApi, oldGame, oldData, oldTime, oldPrint = _G.api, _G.game, _G.data, os.time, print
    local oldMap = package.loaded.telecom_map
    local fakeApi, interface, fixture = fakeEngine()
    local now, logs, commands, displayed, requestRefresh = 100, 0, {}, nil, nil
    os.time = function() return now end
    _G.api, _G.game = fakeApi, { interface = interface, config = {} }
    _G.print = function() logs = logs + 1 end
    package.loaded.telecom_map = nil
    dofile("res/config/game_script/telecom_growth.lua")
    local engine = data()
    assert(package.loaded.telecom_map == nil)
    assert(engine.save().error and engine.save().year == nil and engine.save().globalBonus == nil)
    fixture.year = nil
    engine.update()
    assert(engine.save().error and engine.save().year == nil and engine.save().globalBonus == nil)
    assert(game.config.townDevelopInterval == nil and logs == 1)
    fixture.year, now = 2023, now + 5
    engine.update()
    local good = engine.save()
    assert(not good.error and good.coveredTowns == 1 and game.config.townDevelopInterval == good.interval)
    engine.update()
    assert(engine.save().revision == good.revision)
    now = now + 5
    engine.update()
    assert(engine.save().revision == good.revision + 1)
    good = engine.save()
    fixture.year = nil
    engine.handleEvent("test", "telecom_network", "refresh", {})
    local failed = engine.save()
    assert(failed.error and failed.coveredTowns == 1 and failed.year == good.year)
    assert(failed.revision > good.revision and not good.error and logs == 1)
    assert(game.config.townDevelopInterval == good.interval)
    engine.handleEvent("test", "telecom_network", "refresh", {})
    assert(logs == 1 and engine.save().revision == failed.revision)
    fixture.year = 2023
    engine.handleEvent("test", "telecom_network", "refresh", {})
    assert(not engine.save().error)
    fixture.badPosition = true
    engine.handleEvent("test", "telecom_network", "refresh", {})
    assert(engine.save().error and logs == 2)
    engine.handleEvent("test", "telecom_network", "refresh", {})
    assert(logs == 2)
    fixture.badPosition = false
    engine.load(good)
    engine.update()
    assert(engine.save().revision > good.revision)
    local saved = engine.save()

    package.loaded.telecom_map = { new = function(callback)
        requestRefresh = callback
        return { update = function(self, s) displayed = s end }
    end }
    fakeApi.cmd = {
        make = { sendScriptEvent = function(src, id, name, param)
            return { src = src, id = id, name = name, param = param }
        end },
        sendCommand = function(command) commands[#commands + 1] = command end,
    }
    -- GUI has no engine-reading interface and must never write config, including in pause.
    _G.game = { config = setmetatable({}, { __newindex = function() error("GUI config write") end }) }
    local gui = data()
    gui.load(saved)
    gui.guiInit()
    gui.guiUpdate()
    assert(displayed == saved and #commands == 1)
    requestRefresh()
    requestRefresh()
    assert(#commands == 1)
    gui.guiUpdate()
    assert(#commands == 2 and commands[2].id == "telecom_network" and commands[2].name == "refresh")
    gui.guiHandleEvent("constructionBuilder", "builder.proposalCreate", {})
    gui.guiUpdate()
    assert(#commands == 2)
    gui.guiHandleEvent("bulldozer", "builder.apply", {})
    gui.guiUpdate()
    assert(#commands == 3 and displayed == saved)
    serializable(saved)
    _G.api, _G.game, _G.data, os.time, _G.print = oldApi, oldGame, oldData, oldTime, oldPrint
    package.loaded.telecom_map = oldMap
end)

print(tostring(passed) .. " tests passed")
