-- Run from the repository root: lua tests/telecom_export_test.lua
-- The renderer stub deliberately tests the exporter independently of the GUI.
package.path = "./res/scripts/?.lua;" .. package.path
local realIO, realOS, realAPI = io, os, api
local previousView = package.loaded.telecom_export_view
local passed, failed = 0, 0
local seenPrefix, seenSuffix
local view = {}
function view.escape(value)
    return (tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        :gsub('"', "&quot;"):gsub("'", "&#39;"))
end
function view.number(value)
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge)
    if value == 0 then return "0" end
    return string.format("%.10g", value)
end
function view.prefix(snapshot)
    seenPrefix = snapshot
    local b = snapshot.bounds
    return "<!doctype html><html><head><meta charset='utf-8'></head><body><aside>"
        .. view.escape(snapshot.nodes[1].name) .. ":" .. snapshot.year .. "</aside>"
        .. "<svg id='map' viewBox='" .. table.concat({ view.number(b.minX), view.number(-b.maxY),
            view.number(b.maxX - b.minX), view.number(b.maxY - b.minY) }, " ")
        .. "'><defs><clipPath id='world-bounds'><rect x='" .. view.number(b.minX)
        .. "' y='" .. view.number(-b.maxY) .. "' width='" .. view.number(b.maxX - b.minX)
        .. "' height='" .. view.number(b.maxY - b.minY) .. "'/></clipPath></defs>"
        .. "<g id='geography' clip-path='url(#world-bounds)'>"
end
function view.suffix(snapshot)
    seenSuffix = snapshot
    return "</g><g id='telecom'><text>" .. view.escape(snapshot.nodes[1].name)
        .. "</text></g></svg></body></html>"
end
package.loaded.telecom_export_view = view
local exporter = require "telecom_export"

local function contains(text, expected)
    assert(type(text) == "string" and text:find(expected, 1, true),
        "missing " .. expected .. " in " .. tostring(text):sub(1, 300))
end

local function snapshot()
    return { year = 2026, revision = 4, bounds = { minX = -20, maxX = 60, minY = -10, maxY = 30 },
        nodes = { { id = 1, name = "A<&\"'", x = 2, y = 3, z = 4,
            services = { { name = "FTTH", radius = 30, active = true, townIds = { 2 } } } } },
        towns = { { id = 2, name = "Town", x = 5, y = 6, z = 7 } },
        coverage = { [2] = { hasFixed = true, hasMobile = false, fixedBonus = 0.2, mobileBonus = 0 } },
        globalBonus = 0.2, coveredTowns = 1 }
end

local function filesystem()
    local fs = { files = {}, handles = {}, writes = 0, flushes = 0, closes = 0, renames = 0,
        removes = 0, opens = 0, maxWrite = 0, writeBytes = 0 }
    function fs.open(path, mode)
        fs.opens = fs.opens + 1
        if fs.onOpen then fs.onOpen(path, mode) end
        if mode == "rb" and not fs.files[path] then return nil, "No such file", 2 end
        if fs.denyProbe and mode == "rb" then return nil, "Permission denied", 13 end
        if fs.denyOpen and mode == "wb" then return nil, "Permission denied", 13 end
        if mode == "wb" then
            assert(not fs.files[path], "overwrote an existing partial")
            fs.files[path] = ""
        end
        local f = { path = path, closed = false, mode = mode }
        fs.handles[#fs.handles + 1] = f
        function f:write(text)
            assert(not self.closed and self.mode == "wb")
            fs.writes = fs.writes + 1
            fs.maxWrite = math.max(fs.maxWrite, #text)
            fs.writeBytes = fs.writeBytes + #text
            if fs.writeFailure then
                fs.files[path] = fs.files[path] .. text:sub(1, 3)
                if fs.writeFailure == "throw" then error("write exploded") end
                if fs.writeFailure == "false" then return false, "disk full" end
                return nil, "disk full"
            end
            fs.files[path] = fs.files[path] .. text
            return self
        end
        function f:flush()
            assert(not self.closed)
            fs.flushes = fs.flushes + 1
            if fs.flushFailure == "throw" then error("flush exploded") end
            if fs.flushFailure == "false" then return false, "flush failed" end
            if fs.flushFailure then return nil, "flush failed" end
            return true
        end
        function f:close()
            assert(not self.closed, "close twice")
            fs.closes = fs.closes + 1
            if fs.closeFailure and (self.mode == "wb" or fs.failProbeClose) then
                local failure = fs.closeFailure
                if fs.closeOnce then fs.closeFailure = nil end
                if fs.closeActuallyClosed then self.closed = true end
                if failure == "throw" then error("close exploded") end
                if failure == "nil" then return nil, "close failed" end
                return false, "close failed"
            end
            self.closed = true
            return true
        end
        return f
    end
    function fs.remove(path)
        fs.removes = fs.removes + 1
        if fs.removeFailure then return false, "remove failed" end
        assert(fs.files[path], "remove unowned or already removed file")
        fs.files[path] = nil
        return true
    end
    function fs.rename(from, to)
        fs.renames = fs.renames + 1
        if fs.renameFailure == "throw" then error("rename exploded") end
        if fs.renameFailure == "false" then return false, "rename failed" end
        if fs.renameFailure then return nil, "rename failed" end
        assert(fs.files[from], "missing partial")
        assert(not fs.files[to], "overwrote an existing export")
        for _, handle in ipairs(fs.handles) do assert(handle.closed, "publication with an open handle") end
        fs.files[to], fs.files[from] = fs.files[from], nil
        return true
    end
    function fs.install()
        io = { open = fs.open, type = function(f) return f.closed and "closed file" or "file" end }
        os = { remove = fs.remove, rename = fs.rename, date = function() return "20260911-213503" end }
    end
    function fs.clean()
        for path in pairs(fs.files) do assert(not path:match("%.part$"), "partial left: " .. path) end
        for _, handle in ipairs(fs.handles) do assert(handle.closed, "leaked handle") end
    end
    return fs
end

local function engine(edgeCount, getHeight)
    local stats = { probes = 0, edges = 0, enumerations = 0, calls = 0, positions = {} }
    -- Every API call invalidates all previously returned vectors, including
    -- edge tangents. This models the native userdata aliasing without TF2.
    local p, t0, t1, shared = {}, {}, {}, {}
    local enumerating = false
    local function invalidate()
        local _, main = coroutine.running()
        assert(main, "engine API called in coroutine")
        stats.calls = stats.calls + 1
        for _, v in ipairs({ p, t0, t1 }) do v.x, v.y, v.z = 999999, 999999, 999999 end
        for key in pairs(shared) do shared[key] = nil end
    end
    local types = { TERRAIN = 1, BASE_EDGE = 2, BASE_NODE = 3, BASE_EDGE_TRACK = 4 }
    api = { type = { ComponentType = types, Vec2f = { new = function(x, y)
        invalidate()
        return { x = x, y = y }
    end } }, engine = {
        util = { getWorld = function() invalidate(); return 0 end },
        entityExists = function() invalidate(); return true end,
        terrain = { getHeightAt = function(position)
            invalidate()
            stats.probes = stats.probes + 1
            stats.positions[#stats.positions + 1] = { x = position.x, y = position.y }
            return getHeight and getHeight(position.x, position.y, stats.probes) or 120
        end },
        forEachEntityWithComponent = function(callback, component)
            invalidate()
            assert(component == types.BASE_EDGE)
            stats.enumerations = stats.enumerations + 1
            enumerating = true
            for id = 1, edgeCount or 0 do callback(id) end
            enumerating = false
        end,
        getComponent = function(id, component)
            assert(not enumerating, "component fetched inside enumeration callback")
            invalidate()
            if component == types.TERRAIN then shared.waterLevel = 100; return shared end
            if component == types.BASE_EDGE then
                stats.edges = stats.edges + 1
                shared.node0, shared.node1 = 1001, 1002
                t0.x, t0.y, t0.z = 30, 60, 9
                t1.x, t1.y, t1.z = 90, -30, 6
                shared.tangent0, shared.tangent1 = t0, t1
                return shared
            end
            if component == types.BASE_NODE then
                p.x, p.y, p.z = id == 1001 and 10 or 100, id == 1001 and 20 or 80, 7
                shared.position = p
                return shared
            end
            if component == types.BASE_EDGE_TRACK then return id % 2 == 0 and shared or nil end
            error("unexpected component")
        end,
    } }
    return stats
end

local function run(job, stats, fs)
    local steps, progress = 0, job.progress
    while not job.done do
        steps = steps + 1
        assert(steps < 10000, "job never finished")
        assert(job.path == nil, "published path before success")
        local probes, edges, writes = stats and stats.probes or 0, stats and stats.edges or 0, fs and fs.writeBytes or 0
        local done = job:step()
        assert(done == job.done)
        assert(job.progress >= progress and job.progress >= 0 and job.progress <= 1, "non-monotone progress")
        assert(job.done or job.progress < 1, "premature progress=1")
        assert(type(job.phase) == "string")
        if stats then
            assert(stats.probes - probes <= 256, "unbounded terrain probes")
            assert(stats.edges - edges <= 128, "unbounded edge parsing")
        end
        if fs then assert(fs.writeBytes - writes <= 16384, "unbounded write") end
        progress = job.progress
    end
    assert(job:step() == true)
    return steps
end

local function untilPhase(job, phase)
    for _ = 1, 10000 do
        if job.phase == phase then return end
        assert(not job.done, job.error)
        job:step()
    end
    error("phase not reached: " .. phase)
end

local function noBackground()
    return { outputDirectory = "/exports", terrain = false, roads = false, rails = false }
end

local function decodeBMP(html)
    local encoded = assert(html:match("data:image/bmp;base64,([A-Za-z0-9+/=]+)"), "missing embedded BMP")
    assert(#encoded % 4 == 0)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local indices, bytes = {}, {}
    for i = 1, #alphabet do indices[alphabet:sub(i, i)] = i - 1 end
    for i = 1, #encoded, 4 do
        local a, b, c, d = encoded:sub(i, i), encoded:sub(i + 1, i + 1), encoded:sub(i + 2, i + 2), encoded:sub(i + 3, i + 3)
        local n = indices[a] * 262144 + indices[b] * 4096 + (indices[c] or 0) * 64 + (indices[d] or 0)
        bytes[#bytes + 1] = string.char(n // 65536 % 256)
        if c ~= "=" then bytes[#bytes + 1] = string.char(n // 256 % 256) end
        if d ~= "=" then bytes[#bytes + 1] = string.char(n % 256) end
    end
    local bmp = table.concat(bytes)
    assert(bmp:sub(1, 2) == "BM")
    assert(string.unpack("<I4", bmp, 3) == #bmp)
    assert(string.unpack("<I4", bmp, 11) == 54)
    assert(string.unpack("<I4", bmp, 15) == 40)
    local width, height = string.unpack("<i4i4", bmp, 19)
    assert(string.unpack("<I2", bmp, 27) == 1)
    assert(string.unpack("<I2", bmp, 29) == 24)
    assert(string.unpack("<I4", bmp, 31) == 0)
    local stride = (width * 3 + 3) // 4 * 4
    assert(#bmp == 54 + stride * height)
    assert(string.unpack("<I4", bmp, 35) == stride * height)
    local function pixel(x, y)
        local offset = 55 + y * stride + x * 3
        local b, g, r = bmp:byte(offset, offset + 2)
        return r, g, b
    end
    for y = 0, height - 1 do
        assert(bmp:sub(55 + y * stride + width * 3, 54 + (y + 1) * stride) == string.rep("\0", stride - width * 3))
    end
    return width, height, pixel
end

local function test(name, fn)
    local prefix, suffix = view.prefix, view.suffix
    seenPrefix, seenSuffix = nil, nil
    local ok, err = xpcall(fn, debug.traceback)
    io, os, api = realIO, realOS, realAPI
    view.prefix, view.suffix = prefix, suffix
    if ok then passed = passed + 1; print("ok - " .. name)
    else failed = failed + 1; print("not ok - " .. name .. "\n" .. tostring(err)) end
end

test("bounded steps, progress, snapshot freeze, captured io/os and HTML escaping", function()
    local fs, input, opts = filesystem(), snapshot(), noBackground()
    fs.install()
    api = nil
    local job = exporter.new(input, opts)
    assert(not job.done and job.error == nil and job.path == nil and job.progress == 0)
    assert(fs.opens == 0, "new performs file work")
    input.year, input.nodes[1].name, input.bounds.maxX = 1900, "mutated", 999
    input.nodes[1].services[1].townIds[1] = 999
    opts.outputDirectory, opts.terrain = "/other", true
    io, os = realIO, realOS
    run(job, nil, fs)
    assert(not job.error and job.progress == 1 and job.phase == "done")
    assert(job.path:match("^/exports/telecom_map_20260911%-213503_%d+%.html$"))
    local html = fs.files[job.path]
    contains(html, "A&lt;&amp;&quot;&#39;:2026")
    contains(html, "viewBox='-20 -30 80 40'")
    assert(seenPrefix == seenSuffix and seenPrefix ~= input)
    assert(seenSuffix.nodes[1].services[1].townIds[1] == 2)
    assert(#seenPrefix.nodes == 1)
    local count = 0
    for _ in pairs(seenPrefix.bounds) do count = count + 1 end
    assert(count == 4)
    assert(not pcall(function() seenPrefix.year = 1 end))
    assert(not pcall(function() seenPrefix.nodes[1].name = "changed" end))
    assert(fs.flushes == 1 and fs.renames == 1)
    job:cancel()
    assert(fs.files[job.path] == html, "cancel removed published output")
    fs.clean()
end)

test("reject invalid snapshot and options before any engine/file work", function()
    local fs = filesystem(); fs.install(); api = nil
    local cases = {
        function(s) s.error = "stale" end,
        function(s) s.bounds = nil end,
        function(s) s.bounds.maxX = s.bounds.minX end,
        function(s) s.bounds.minX, s.bounds.maxX = -1e308, 1e308 end,
        function(s) s.bounds.maxY = 0 / 0 end,
        function(s) s.year = nil end,
        function(s) s.year = 0 end,
        function(s) s.year = -2026 end,
        function(s) s.year = math.huge end,
        function(s) s.year = 2026.5 end,
        function(s) s.nodes[1].x = math.huge end,
        function(s) s.coverage[2].fixedBonus = 0 / 0 end,
        function(s) s.nodes[1].services[1].townIds[1] = -math.huge end,
        function(s) s.extra = function() end end,
        function(s) s.extra = s end,
    }
    for _, mutate in ipairs(cases) do
        local input = snapshot(); mutate(input)
        local job = exporter.new(input, noBackground())
        assert(job.done and job.error and not job.path)
        assert(job:step()); job:cancel()
    end
    for _, opts in ipairs({ { terrainResolution = 513 }, { terrainResolution = 0 },
        { terrainResolution = 1.5 }, { terrainResolution = false }, { terrainResolution = 0 / 0 },
        { terrainResolution = "16" }, { outputDirectory = "" }, { outputDirectory = "bad\0path" },
        { roads = 1 }, { terrain = "false" }, { rails = {} } }) do
        local job = exporter.new(snapshot(), opts)
        assert(job.done and job.error and not job.path)
    end
    local job = exporter.new(nil)
    assert(job.done and job.error)
    assert(fs.opens == 0)
end)

test("default mod-root directory and default 256 terrain resolution", function()
    local fs = filesystem(); fs.install()
    local stats = engine(0)
    local job = exporter.new(snapshot())
    run(job, stats, fs)
    assert(not job.error, job.error)
    assert(job.path:match("/map_exports/telecom_map_"))
    local width, height = decodeBMP(fs.files[job.path])
    assert(width == 256 and height == 128 and stats.probes == 32768)
    fs.clean()
end)

test("aliased engine vectors, cubic coordinates, road/rail styles and batching", function()
    local fs = filesystem(); fs.install()
    local stats = engine(300)
    local job = exporter.new(snapshot(), { outputDirectory = "/exports", terrain = false })
    run(job, stats, fs)
    assert(not job.error and #job.warnings == 0, job.error)
    assert(stats.enumerations == 1 and stats.edges == 300)
    local html = fs.files[job.path]
    contains(html, "<g id='roads' fill='none' stroke='#697d89' stroke-width='1.1px'>")
    contains(html, "<g id='rails' fill='none' stroke='#334551' stroke-width='1.1px'>")
    local roadPaths = assert(html:match("<g id='roads'.->(.-)</g>"))
    local railPaths = assert(html:match("<g id='rails'.->(.-)</g>"))
    for _, paths in ipairs({ roadPaths, railPaths }) do
        local _, count = paths:gsub("<path ", "")
        assert(count == 150)
        contains(paths, "vector-effect='non-scaling-stroke' d='M 10 -20 C 20 -40 70 -90 100 -80'")
        assert(not paths:find("999999", 1, true))
    end
    fs.clean()
end)

test("road and rail options independently filter their groups", function()
    for _, kind in ipairs({ "roads", "rails" }) do
        local fs = filesystem(); fs.install()
        engine(2)
        local opts = noBackground(); opts[kind] = true
        local job = exporter.new(snapshot(), opts); run(job)
        assert(not job.error, job.error)
        local html = fs.files[job.path]
        local other = kind == "roads" and "rails" or "roads"
        contains(assert(html:match("<g id='" .. kind .. "'.->(.-)</g>")), "<path ")
        assert(not assert(html:match("<g id='" .. other .. "'.->(.-)</g>")):find("<path ", 1, true))
        fs.clean()
    end
end)

test("BMP non-square orientation, world dimensions, row padding and flat terrain", function()
    for _, resolution in ipairs({ 1, 3, 17, 512 }) do
        local fs = filesystem(); fs.install()
        local stats = engine(0, function() return 120 end)
        local job = exporter.new(snapshot(), { outputDirectory = "/exports", terrainResolution = resolution,
            roads = false, rails = false })
        run(job, stats, fs)
        assert(not job.error, job.error)
        local html = fs.files[job.path]
        contains(html, "<image x='-20' y='-30' width='80' height='40' preserveAspectRatio='none'")
        local w, h, pixel = decodeBMP(html)
        assert(w == resolution and h == math.max(1, math.floor(resolution / 2 + 0.5)))
        local first = table.concat({ pixel(0, 0) }, ",")
        for y = 0, h - 1 do
            for x = 0, w - 1 do assert(table.concat({ pixel(x, y) }, ",") == first) end
        end
        assert(stats.positions[1].x > -20 and stats.positions[1].y > -10)
        assert(stats.positions[#stats.positions].x < 60 and stats.positions[#stats.positions].y < 30)
        fs.clean()
    end
    local fs = filesystem(); fs.install()
    engine(0, function(_, y) return y < 10 and 90 or 120 end)
    local input = snapshot(); input.bounds = { minX = 0, maxX = 4, minY = 0, maxY = 20 }
    local job = exporter.new(input, { outputDirectory = "/exports", terrainResolution = 10, roads = false, rails = false })
    run(job)
    assert(not job.error, job.error)
    local w, h, pixel = decodeBMP(fs.files[job.path])
    assert(w == 2 and h == 10)
    local southR, _, southB = pixel(0, 0)
    local northR, _, northB = pixel(0, 9)
    assert(southB > southR and northR > northB, "BMP flipped north/south or water assumed at zero")
    fs.clean()
end)

test("northwest hillshade and altitude affect land colors", function()
    local colors = {}
    for i, sample in ipairs({ function(x, y) return 500 + x - y end,
        function(x, y) return 500 - x + y end, function() return 1500 end }) do
        local fs = filesystem(); fs.install(); engine(0, sample)
        local input = snapshot(); input.bounds = { minX = -10, maxX = 10, minY = -10, maxY = 10 }
        local job = exporter.new(input, { outputDirectory = "/exports", terrainResolution = 3, roads = false, rails = false })
        run(job); assert(not job.error, job.error)
        local _, _, pixel = decodeBMP(fs.files[job.path]); colors[i] = { pixel(1, 1) }
        fs.clean()
    end
    assert(colors[1][1] > colors[2][1], "northwest-facing slope should be lighter")
    assert(colors[3][3] > colors[1][3], "altitude color ramp missing")
end)

test("optional API failures warn visibly with escaped text, never a truncated image", function()
    for _, scenario in ipairs({ "missing-api", "water", "height", "enumeration", "edge" }) do
        local fs = filesystem(); fs.install()
        engine(3)
        local attack = "<script>bad&\"'%</script>"
        if scenario == "missing-api" then api = nil
        elseif scenario == "water" then
            local get = api.engine.getComponent
            api.engine.getComponent = function(id, component)
                if component == api.type.ComponentType.TERRAIN then return {} end
                return get(id, component)
            end
        elseif scenario == "height" then
            local calls = 0
            api.engine.terrain.getHeightAt = function()
                calls = calls + 1
                if calls > 256 then error(attack) end
                return 123
            end
        elseif scenario == "enumeration" then
            api.engine.forEachEntityWithComponent = function(callback) callback(1); error(attack) end
        else
            local get = api.engine.getComponent
            api.engine.getComponent = function(id, component)
                if component == api.type.ComponentType.BASE_EDGE and id == 1 then error(attack) end
                return get(id, component)
            end
        end
        local job = exporter.new(snapshot(), { outputDirectory = "/exports", terrainResolution = 32 })
        run(job)
        assert(not job.error and #job.warnings > 0, job.error)
        local html = fs.files[job.path]
        contains(html, "id='export-warnings'")
        contains(html, "</section></body></html>")
        if scenario == "missing-api" or scenario == "water" or scenario == "height" then
            assert(not html:find("data:image/bmp", 1, true), "partial terrain image retained")
        end
        if scenario == "height" or scenario == "enumeration" or scenario == "edge" then
            contains(html, view.escape(attack))
            assert(not html:find(attack, 1, true))
        end
        if scenario == "edge" then
            local _, count = html:gsub("<path ", "")
            assert(count == 2, "one bad edge discarded valid neighbors")
        end
        fs.clean()
    end
end)

test("cancel before opening, during work/writes, and before publication", function()
    for _, phase in ipairs({ "open", "terrain-sample", "terrain-encode", "edge-parse", "roads", "flush", "publish" }) do
        local fs = filesystem(); fs.install(); engine(300)
        local job = exporter.new(snapshot(), { outputDirectory = "/exports", terrainResolution = 32 })
        untilPhase(job, phase)
        job:cancel(); job:cancel()
        assert(job.done and job.error and not job.path and job.phase == "cancelled")
        local opens = fs.opens
        assert(job:step() and fs.opens == opens)
        assert(fs.renames == 0 and next(fs.files) == nil)
        fs.clean()
    end
end)

test("nonfinite optional engine data cannot leak NaN/Infinity into SVG/BMP", function()
    for _, scenario in ipairs({ "water", "height", "position", "tangent" }) do
        local fs = filesystem(); fs.install(); engine(2)
        local get = api.engine.getComponent
        if scenario == "height" then api.engine.terrain.getHeightAt = function() return math.huge end
        else
            api.engine.getComponent = function(id, component)
                local value = get(id, component)
                local types = api.type.ComponentType
                if scenario == "water" and component == types.TERRAIN then value.waterLevel = 0 / 0 end
                if scenario == "position" and component == types.BASE_NODE then value.position.x = -math.huge end
                if scenario == "tangent" and component == types.BASE_EDGE then value.tangent0.z = 0 / 0 end
                return value
            end
        end
        local job = exporter.new(snapshot(), { outputDirectory = "/exports", terrainResolution = 4 })
        run(job)
        assert(not job.error and #job.warnings > 0, job.error)
        local html = fs.files[job.path]
        contains(html, "id='export-warnings'")
        if scenario == "water" or scenario == "height" then
            assert(not html:find("data:image/bmp", 1, true))
        else
            assert(not html:find("<path ", 1, true))
            decodeBMP(html)
        end
        fs.clean()
    end
end)

test("write, flush, close and rename false/nil/exception never publish success", function()
    for _, operation in ipairs({ "write", "flush", "close", "rename" }) do
        for _, mode in ipairs({ "false", "nil", "throw" }) do
            local fs = filesystem(); fs.install(); api = nil
            fs[operation .. "Failure"] = mode
            fs.closeOnce = true
            local job = exporter.new(snapshot(), noBackground())
            run(job, nil, fs)
            assert(job.done and job.error and not job.path and job.progress < 1)
            contains(job.error, operation)
            assert(next(fs.files) == nil)
            if operation ~= "rename" then assert(fs.renames == 0) end
            fs.clean()
        end
    end
end)

test("close failure on an already closed native handle and cleanup retry", function()
    local fs = filesystem(); fs.install()
    fs.closeFailure, fs.closeActuallyClosed = true, true
    local job = exporter.new(snapshot(), noBackground()); run(job)
    assert(job.error and not job.path and fs.closes == 1)
    fs.clean()
    fs = filesystem(); fs.install()
    fs.closeFailure, fs.removeFailure = true, true
    job = exporter.new(snapshot(), noBackground()); run(job)
    assert(job.error and not job.path and #job.warnings >= 2)
    assert(job.cleanupError and job.cleanupError:find(".part", 1, true))
    fs.closeFailure, fs.removeFailure = nil, nil
    job:cancel()
    assert(not job.cleanupError, "successful retry must clear cleanup error state")
    fs.clean()
    assert(next(fs.files) == nil)
end)

test("open/probe failures and renderer failures close/remove owned partial only", function()
    for _, failure in ipairs({ "open", "probe", "prefix", "suffix" }) do
        local fs = filesystem(); fs.install()
        local prefix, suffix = view.prefix, view.suffix
        if failure == "open" then fs.denyOpen = true
        elseif failure == "probe" then
            fs.onOpen = function(path, mode)
                if mode == "rb" then fs.files[path] = "unreadable" end
            end
            fs.denyProbe = true
        elseif failure == "prefix" then view.prefix = function() error("prefix failed") end
        else view.suffix = function() error("suffix failed") end end
        local job = exporter.new(snapshot(), noBackground()); run(job)
        assert(job.error and not job.path and fs.renames == 0)
        view.prefix, view.suffix = prefix, suffix
        fs.clean()
    end
end)

test("timestamp collisions, existing partials, simultaneous jobs and late collisions", function()
    local fs = filesystem(); fs.install()
    local occupied, occupiedPartial
    fs.onOpen = function(path, mode)
        if mode == "rb" and not occupied then
            occupied = path; fs.files[path] = "original HTML"
        elseif mode == "rb" and path:match("%.part$") and not occupiedPartial then
            occupiedPartial = path; fs.files[path] = "original partial"
        end
    end
    local a = exporter.new(snapshot(), noBackground())
    local b = exporter.new(snapshot(), noBackground())
    untilPhase(a, "publish"); untilPhase(b, "publish")
    fs.onOpen = nil
    local late
    for path in pairs(fs.files) do
        if path:match("%.part$") and path ~= occupiedPartial then
            late = path:sub(1, -6); fs.files[late] = "late writer"; break
        end
    end
    run(a); run(b)
    assert(not a.error and not b.error and a.path ~= b.path)
    assert(a.path ~= late and b.path ~= late)
    assert(fs.files[occupied] == "original HTML" and fs.files[occupiedPartial] == "original partial")
    assert(fs.files[late] == "late writer")
    fs.files[occupiedPartial] = nil
    fs.clean()
end)

test("collision probe close failure is fatal and releases its handle", function()
    local fs = filesystem(); fs.install()
    fs.closeFailure, fs.closeOnce, fs.failProbeClose = true, true, true
    local existing
    fs.onOpen = function(path)
        if not existing then existing = path; fs.files[path] = "existing" end
    end
    local job = exporter.new(snapshot(), noBackground()); run(job)
    assert(job.error and not job.path and fs.files[existing] == "existing")
    assert(fs.renames == 0 and fs.removes == 0)
    fs.clean()
end)

test("large renderer strings are written in bounded blocks", function()
    local fs = filesystem(); fs.install()
    local prefix, suffix = view.prefix, view.suffix
    view.prefix = function(s) return prefix(s) .. string.rep(" ", 80000) end
    view.suffix = function(s) return string.rep(" ", 80000) .. suffix(s) end
    local job = exporter.new(snapshot(), noBackground()); run(job, nil, fs)
    assert(not job.error and fs.maxWrite == 16384 and #fs.files[job.path] > 160000, job.error)
    fs.clean()
end)

test("real Lua io write/flush/close/rename smoke test in existing temporary directory", function()
    io, os, api = realIO, realOS, nil
    local opts = noBackground()
    opts.outputDirectory = os.getenv("TMPDIR") or "/tmp"
    local job = exporter.new(snapshot(), opts)
    run(job)
    assert(not job.error and job.path, job.error)
    local file = assert(io.open(job.path, "rb"))
    local html = assert(file:read("*a"))
    assert(file:close())
    assert(os.remove(job.path))
    contains(html, "<!doctype html>")
    contains(html, "</body></html>")
end)

io, os, api = realIO, realOS, realAPI
package.loaded.telecom_export_view = previousView
print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
