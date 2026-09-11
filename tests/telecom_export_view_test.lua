package.path = "res/scripts/?.lua;" .. package.path
local view = require "telecom_export_view"
local network = require "telecom_network"
local passed = 0
local function test(name, fn) fn(); passed = passed + 1; print("ok - " .. name) end
local function contains(text, value) assert(text:find(value, 1, true), "missing " .. value) end
local hostile = '</script><img src=x onerror="window.__telecomInjected=true"> & "Town"'
local snapshot = network.computeSnapshot({ year = 2023, terrainSize = { x = 32, y = 16 },
    nodes = {
        { id = 1, kind = "NRA", name = "Cuivre", x = -1600, y = 400 },
        { id = 2, kind = "NRO", name = "Fibre", x = 0, y = 100 },
        { id = 3, kind = "ANTENNA", name = "Radio", x = 1700, y = -200, params = { tech_2g = 1, tech_5g = 1 } },
        { id = 4, kind = "ANTENNA", name = "Inactive", x = -2700, y = -1300, params = {} },
    }, towns = { { id = 11, name = hostile, x = 1200, y = 100 }, { id = 12, name = "Ouest", x = -2400, y = 800 } },
}, 10)
local html = view.prefix(snapshot) .. '<g id="terrain"><rect x="-4096" y="-2048" width="8192" height="4096" fill="#d1dfbe"/></g><g id="roads"><path d="M-3000 1000 C-1000 0 1000 1000 3000 -1000" fill="none" stroke="#fff" stroke-width="30"/></g><g id="rails"></g>' .. view.suffix(snapshot)

test("HTML escapes savegame names in text and attributes", function()
    assert(not html:find(hostile, 1, true))
    contains(html, '&lt;/script&gt;&lt;img src=x onerror=&quot;window.__telecomInjected=true&quot;&gt; &amp; &quot;Town&quot;')
    assert(view.escape("a\0b\1c") == "abc")
    local _, scripts = html:gsub('<script>', '')
    assert(scripts == 1)
end)
test("world coordinates retain uniform scale and north-up rectangular bounds", function()
    contains(html, 'viewBox="-4096 -2048 8192 4096"')
    contains(html, 'cx="-1600" cy="-400" r="1500"')
    contains(html, 'cx="1700" cy="200" r="2000"')
    assert(view.number(0) == "0" and view.number(1000) == "1000")
    assert(not pcall(view.number, math.huge))
    assert(not pcall(view.number, 0/0))
end)
test("marker shapes and inactive equipment are preserved", function()
    contains(html, '<rect x="-5" y="-5" width="10" height="10"/>')
    contains(html, '<path d="M0 -7 L7 6 L-7 6 Z"/>')
    contains(html, '<circle r="5.5"/>')
    contains(html, 'id="node-4"')
    contains(html, 'fill="#879196"')
    assert(not html:find('data-node="node-4"', 1, true))
end)
test("only active service discs are emitted with entity and technology references", function()
    local _, circles = html:gsub('class="coverage"', '')
    assert(circles == 4)
    contains(html, 'data-node="node-3" data-kind="ANTENNA" data-tech="tech_5g"')
    assert(not html:find('data-node="node-3" data-kind="ANTENNA" data-tech="tech_3g"', 1, true))
end)
test("standalone controls, selection details, clipping and responsive styles are present", function()
    contains(html, 'id="detail-node-3"')
    contains(html, 'id="detail-town-11"')
    contains(html, 'id="only-selected"')
    contains(html, 'id="opacity"')
    contains(html, 'clip-path="url(#world-bounds)"')
    contains(html, '@media(max-width:760px)')
    assert(not html:find('<script src=', 1, true) and not html:find('fetch(', 1, true))
end)
test("unknown limits are explicitly disclosed", function()
    snapshot.boundsEstimated = true
    contains(view.prefix(snapshot), 'limites du territoire estimees')
    snapshot.boundsEstimated = false
end)

if arg[1] then
    test("real exporter and viewer produce a complete atlas with an embedded terrain", function()
        local original = _G.api
        local types = { TERRAIN = 1, BASE_EDGE = 2, BASE_NODE = 3, BASE_EDGE_TRACK = 4 }
        _G.api = { type = { ComponentType = types, Vec2f = { new = function(x,y) return {x=x,y=y} end } }, engine = {
            util = { getWorld = function() return 0 end },
            entityExists = function() return true end,
            terrain = { getHeightAt = function(p) return 120 + 55*math.sin(p.x/650)*math.cos(p.y/450) end },
            forEachEntityWithComponent = function(callback) callback(10); callback(11) end,
            getComponent = function(id, kind)
                if kind == types.TERRAIN then return { waterLevel = 100 } end
                if kind == types.BASE_EDGE then return { node0 = id==10 and 101 or 103, node1 = id==10 and 102 or 104,
                    tangent0 = {x=4500,y=5000,z=0}, tangent1 = {x=4500,y=-1000,z=0} } end
                if kind == types.BASE_NODE then return {position={x=id%2==1 and -3000 or 3000,y=(id%2==1 and -1000 or 1000)+(id>102 and 100 or 0),z=120}} end
                if kind == types.BASE_EDGE_TRACK and id==11 then return {} end
            end,
        } }
        local job = require("telecom_export").new(snapshot, { outputDirectory=arg[1], terrainResolution=128 })
        for step=1,5000 do if job.done then break end; job:step() end
        _G.api = original
        assert(job.done and not job.error, tostring(job.error))
        assert(#job.warnings == 0)
        local input = assert(io.open(job.path,"rb")); html=assert(input:read("*a")); assert(input:close())
        contains(html, 'data:image/bmp;base64,')
        contains(html, 'data-node="node-3"')
        contains(html, '<script>')
        assert(os.remove(job.path))
    end)
    local path = arg[1] .. "/telecom-export-test.html"
    local file = assert(io.open(path, "wb")); assert(file:write(html)); assert(file:close())
    print("Fixture: " .. path)
end
print(passed .. " export view tests passed")
