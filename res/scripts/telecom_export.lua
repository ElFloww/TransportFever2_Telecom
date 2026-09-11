-- Standalone export, implemented independently (no Cartograph source copied).
-- Call step() on the GUI thread, never in a coroutine. Progress is in [0, 1].
-- Lua 5.1/5.2/5.3 standard libraries; only telecom_export_view is required.
-- io/os are captured per job; tests/telecom_export_test.lua uses a stub renderer.
local exporter = {}
local source = debug.getinfo(1, "S").source:gsub("\\", "/")
local root = source:match("^@(.+)/res/scripts/telecom_export%.lua$")
if source == "@res/scripts/telecom_export.lua" then root = "." end
local sequence = 0
local WRITE_BYTES, PROBES, EDGES, BMP_ROWS = 16384, 256, 128, 8

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function checked(n, label)
    assert(finite(n), label .. " must be finite")
    return n
end

-- Private plain tables isolate caller mutations without version-specific proxies.
-- Only the job closure and trusted renderer receive the copy; it is not read-only.
local function deepCopy(value, active, copies)
    local kind = type(value)
    if kind == "number" then return checked(value, "snapshot number") end
    if kind ~= "table" then
        assert(kind == "nil" or kind == "boolean" or kind == "string", "snapshot must contain plain data")
        return value
    end
    assert(not active[value], "snapshot contains a cycle")
    if copies[value] then return copies[value] end
    local data = {}
    active[value], copies[value] = true, data
    for key, item in next, value do
        assert(type(key) == "string" or type(key) == "number", "invalid snapshot key")
        data[deepCopy(key, active, copies)] = deepCopy(item, active, copies)
    end
    active[value] = nil
    return data
end

local function littleEndian(n, size)
    local bytes = {}
    for i = 1, size do
        bytes[i] = string.char(n % 256)
        n = math.floor(n / 256)
    end
    return table.concat(bytes)
end

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(bytes)
    local out = {}
    for i = 1, #bytes, 3 do
        local a, b, c = bytes:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local x, y, z, w = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
        out[#out + 1] = alphabet:sub(x + 1, x + 1) .. alphabet:sub(y + 1, y + 1)
            .. (b and alphabet:sub(z + 1, z + 1) or "=")
            .. (c and alphabet:sub(w + 1, w + 1) or "=")
    end
    return table.concat(out)
end

local function vector(v)
    assert(v, "missing vector")
    return { x = checked(v.x, "x"), y = checked(v.y, "y"), z = checked(v.z, "z") }
end

local function edgePath(id, number, roads, rails)
    local engine, types = api.engine, api.type.ComponentType
    if not engine.entityExists(id) then return end
    local edge = assert(engine.getComponent(id, types.BASE_EDGE), "missing BASE_EDGE")
    -- Bindings may reuse the same userdata storage at the very next API call.
    local node0, node1 = checked(edge.node0, "node0"), checked(edge.node1, "node1")
    local t0, t1 = vector(edge.tangent0), vector(edge.tangent1)
    if not engine.entityExists(node0) or not engine.entityExists(node1) then return end
    local a = vector(assert(engine.getComponent(node0, types.BASE_NODE), "missing node0").position)
    local b = vector(assert(engine.getComponent(node1, types.BASE_NODE), "missing node1").position)
    local kind = engine.getComponent(id, types.BASE_EDGE_TRACK) and "rails" or "roads"
    if (kind == "roads" and not roads) or (kind == "rails" and not rails) then return end
    local coords = { a.x, -a.y, a.x + t0.x / 3, -a.y - t0.y / 3,
        b.x - t1.x / 3, -b.y + t1.y / 3, b.x, -b.y }
    for i, n in ipairs(coords) do coords[i] = number(checked(n, "Bezier coordinate")) end
    return kind, "<path vector-effect='non-scaling-stroke' d='M " .. coords[1] .. " " .. coords[2]
        .. " C " .. table.concat(coords, " ", 3) .. "'/>\n"
end

function exporter.new(snapshot, options)
    local job = { done = false, error = nil, path = nil, progress = 0, phase = "open", warnings = {} }
    local open, remove, rename, date, ioType = io.open, os.remove, os.rename, os.date, io.type
    local canRemove, canRename = type(remove) == "function", type(rename) == "function"
    local handle, partial, target, directory, stamp, view, copied, opts, bounds, spanX, spanY
    local pending, pendingOffset, heights, width, height, dx, dy, water, cell, row, carry, heightAt
    local ids, edgeIndex, paths, pathIndex, edgeWarning

    local function warn(message)
        job.warnings[#job.warnings + 1] = tostring(message)
    end

    local function closeHandle()
        if not handle then return true end
        local ok, result, err = pcall(handle.close, handle)
        if ok and result then handle = nil; return true end
        if ioType then
            local typeOK, kind = pcall(ioType, handle)
            if typeOK and kind == "closed file" then handle = nil end
        end
        return false, tostring(ok and (err or "close returned false") or result)
    end

    local function cleanup()
        local errors = {}
        local ok, err = closeHandle()
        if not ok then errors[#errors + 1] = "Cleanup close: " .. err end
        if partial then
            if canRemove then
                local success, result, message = pcall(remove, partial)
                if success and result then partial = nil
                else errors[#errors + 1] = "Cleanup remove " .. partial .. ": " .. tostring(success and message or result) end
            else
                errors[#errors + 1] = "Cleanup remove " .. partial .. ": os.remove unavailable"
            end
        end
        for _, message in ipairs(errors) do warn(message) end
        job.cleanupError = #errors > 0 and table.concat(errors, "\n") or nil
        pending, heights, ids, paths, carry = nil, nil, nil, nil, nil
    end

    local function fail(err)
        job.done, job.error, job.path, job.phase = true, tostring(err), nil, "failed"
        cleanup()
    end

    local function queue(text)
        assert(type(text) == "string", "renderer must return a string")
        assert(not pending, "output already pending")
        pending, pendingOffset = text, 1
    end

    local function advance(phase, progress)
        job.phase = phase
        job.progress = math.max(job.progress, progress)
    end

    local function exists(path)
        local f, message, code = open(path, "rb")
        if f then
            -- Even collision probes own a handle whose close can fail.
            handle = f
            local ok, err = closeHandle()
            assert(ok, "Collision probe close: " .. tostring(err))
            return true
        end
        assert(code == 2, "Cannot check output path: " .. tostring(message))
        return false
    end

    local function candidate()
        sequence = sequence + 1
        return directory .. "/telecom_map_" .. stamp .. string.format("_%06d.html", sequence)
    end

    local ok, err = pcall(function()
        assert(type(snapshot) == "table", "snapshot required")
        assert(not snapshot.error, "snapshot.error: " .. tostring(snapshot.error))
        copied = deepCopy(snapshot, {}, {})
        assert(finite(copied.year) and copied.year > 0 and copied.year % 1 == 0, "invalid snapshot year")
        bounds = assert(copied.bounds, "snapshot bounds required")
        spanX = checked(bounds.maxX, "maxX") - checked(bounds.minX, "minX")
        spanY = checked(bounds.maxY, "maxY") - checked(bounds.minY, "minY")
        assert(finite(spanX) and finite(spanY) and spanX > 0 and spanY > 0, "invalid snapshot bounds")
        assert(options == nil or type(options) == "table", "options must be a table")
        options = options or {}
        opts = {}
        for _, key in ipairs({ "terrain", "roads", "rails" }) do
            assert(options[key] == nil or type(options[key]) == "boolean", "invalid option " .. key)
            opts[key] = options[key] ~= false
        end
        local resolution = options.terrainResolution
        if resolution == nil then resolution = 256 end
        assert(finite(resolution) and resolution % 1 == 0 and resolution >= 1 and resolution <= 512,
            "terrainResolution must be an integer in [1, 512]")
        local span = math.max(spanX, spanY)
        width = math.max(1, math.floor(resolution * (spanX / span) + 0.5))
        height = math.max(1, math.floor(resolution * (spanY / span) + 0.5))
        dx, dy = spanX / width, spanY / height
        assert(dx > 0 and dy > 0, "bounds too small for terrain resolution")
        directory = options.outputDirectory
        if directory == nil then
            assert(root, "Cannot locate mod root from telecom_export.lua source")
            directory = root .. "/map_exports"
        end
        assert(type(directory) == "string" and directory ~= "" and not directory:find("%z"),
            "invalid outputDirectory")
        stamp = date("%Y%m%d-%H%M%S")
        assert(type(stamp) == "string" and stamp:match("^%d+%-%d+$"), "invalid timestamp")
        view = require "telecom_export_view"
        for _, key in ipairs({ "escape", "number", "prefix", "suffix" }) do
            assert(type(view[key]) == "function", "missing view." .. key)
        end
    end)
    if not ok then fail(err) end

    function job:cancel()
        if self.done and self.phase == "done" then return end
        if not self.done then
            self.done, self.error, self.path, self.phase = true, "Export cancelled", nil, "cancelled"
        end
        cleanup()
    end

    function job:step()
        if self.done then return true end
        local success, failure = pcall(function()
            if pending then
                local result, message = handle:write(pending:sub(pendingOffset, pendingOffset + WRITE_BYTES - 1))
                assert(result, "write: " .. tostring(message))
                pendingOffset = pendingOffset + WRITE_BYTES
                if pendingOffset > #pending then pending = nil end
                return
            end
            if self.phase == "open" then
                target = candidate()
                if exists(target) or (canRename and exists(target .. ".part")) then return end
                local message
                partial = canRename and (target .. ".part") or target
                handle, message = open(partial, "wb")
                assert(handle, "open: " .. tostring(message))
                queue(view.prefix(copied))
                advance("terrain-init", 0.02)
            elseif self.phase == "terrain-init" then
                if not opts.terrain then
                    queue("<g id='terrain'></g>\n")
                    advance("edge-enumerate", 0.65)
                    return
                end
                local terrainOK, terrainError = pcall(function()
                    local terrain = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.TERRAIN)
                    water = checked(assert(terrain, "TERRAIN unavailable").waterLevel, "TERRAIN.waterLevel")
                    heightAt = api.engine.terrain.getHeightAt or api.engine.terrain.getBaseHeightAt
                    assert(heightAt ~= nil, "getHeightAt unavailable")
                end)
                if terrainOK then
                    heights, cell = {}, 0
                    advance("terrain-sample", 0.03)
                else
                    warn("Terrain indisponible : " .. tostring(terrainError))
                    queue("<g id='terrain'></g>\n")
                    advance("edge-enumerate", 0.65)
                end
            elseif self.phase == "terrain-sample" then
                local terrainOK, terrainError = pcall(function()
                    for _ = 1, PROBES do
                        if cell == width * height then break end
                        local col, y = cell % width, math.floor(cell / width)
                        -- BMP is bottom-up: sample south to north, at pixel centres.
                        local position = api.type.Vec2f.new(bounds.minX + (col + 0.5) * dx,
                            bounds.minY + (y + 0.5) * dy)
                        local h = checked(heightAt(position), "terrain height")
                        cell = cell + 1
                        heights[cell] = h
                    end
                end)
                if not terrainOK then
                    heights = nil
                    warn("Terrain indisponible : " .. tostring(terrainError))
                    queue("<g id='terrain'></g>\n")
                    advance("edge-enumerate", 0.65)
                else
                    self.progress = 0.03 + 0.47 * cell / (width * height)
                    if cell == width * height then advance("terrain-image", 0.50) end
                end
            elseif self.phase == "terrain-image" then
                local number = view.number
                queue("<g id='terrain'><image x='" .. number(bounds.minX) .. "' y='" .. number(-bounds.maxY)
                    .. "' width='" .. number(spanX) .. "' height='" .. number(spanY)
                    .. "' preserveAspectRatio='none' href='data:image/bmp;base64,")
                local bytes = math.floor((width * 3 + 3) / 4) * 4 * height
                -- BITMAPFILEHEADER + BITMAPINFOHEADER, positive bottom-up dimensions.
                carry = "BM" .. littleEndian(54 + bytes, 4) .. littleEndian(0, 4)
                    .. littleEndian(54, 4) .. littleEndian(40, 4)
                    .. littleEndian(width, 4) .. littleEndian(height, 4)
                    .. littleEndian(1, 2) .. littleEndian(24, 2)
                    .. littleEndian(0, 4) .. littleEndian(bytes, 4)
                    .. littleEndian(2835, 4) .. littleEndian(2835, 4)
                    .. littleEndian(0, 4) .. littleEndian(0, 4)
                row = 0
                advance("terrain-encode", 0.50)
            elseif self.phase == "terrain-encode" then
                local blocks = { carry }
                for _ = 1, BMP_ROWS do
                    if row == height then break end
                    local pixels = {}
                    for col = 0, width - 1 do
                        local h = heights[row * width + col + 1]
                        local r, g, b
                        if h <= water then
                            local depth = math.min(1, (water - h) / 50)
                            r, g, b = 104 - 22 * depth, 153 - 20 * depth, 177 - 13 * depth
                        else
                            local elevation = h - water
                            local low, high = math.min(1, elevation / 300), math.max(0, math.min(1, (elevation - 300) / 1200))
                            r, g, b = 166 + 23 * low + 36 * high, 187 - 10 * low + 44 * high, 137 + 5 * low + 69 * high
                            local left, right = math.max(0, col - 1), math.min(width - 1, col + 1)
                            local south, north = math.max(0, row - 1), math.min(height - 1, row + 1)
                            local gx = (heights[row * width + right + 1] - heights[row * width + left + 1]) / (math.max(1, right - left) * dx)
                            local gy = (heights[north * width + col + 1] - heights[south * width + col + 1]) / (math.max(1, north - south) * dy)
                            gx, gy = math.max(-1e6, math.min(1e6, gx)), math.max(-1e6, math.min(1e6, gy))
                            -- World northwest light: (-1/2, +1/2, sqrt(1/2)).
                            local shade = 0.65 + 0.35 * math.max(0, (0.5 * gx - 0.5 * gy + math.sqrt(0.5)) / math.sqrt(1 + gx * gx + gy * gy))
                            r, g, b = r * shade, g * shade, b * shade
                        end
                        pixels[#pixels + 1] = string.char(math.floor(b + 0.5), math.floor(g + 0.5), math.floor(r + 0.5))
                    end
                    pixels[#pixels + 1] = string.rep("\0", (4 - width * 3 % 4) % 4)
                    blocks[#blocks + 1] = table.concat(pixels)
                    row = row + 1
                end
                local bytes = table.concat(blocks)
                local length = row == height and #bytes or math.floor(#bytes / 3) * 3
                carry = bytes:sub(length + 1)
                queue(base64(bytes:sub(1, length)) .. (row == height and "'/></g>\n" or ""))
                self.progress = 0.50 + 0.15 * row / height
                if row == height then
                    heights, carry = nil, nil
                    advance("edge-enumerate", 0.65)
                end
            elseif self.phase == "edge-enumerate" then
                ids, edgeIndex, paths = {}, 1, { roads = {}, rails = {} }
                if opts.roads or opts.rails then
                    local edgeOK, edgeError = pcall(function()
                        -- Enumeration is one engine call; its callback only copies scalar IDs.
                        api.engine.forEachEntityWithComponent(function(id)
                            ids[#ids + 1] = checked(id, "edge id")
                        end, api.type.ComponentType.BASE_EDGE)
                    end)
                    if not edgeOK then
                        ids = {}
                        warn("Routes/rails indisponibles : " .. tostring(edgeError))
                    end
                end
                advance("edge-parse", 0.66)
            elseif self.phase == "edge-parse" then
                for _ = 1, EDGES do
                    if edgeIndex > #ids then break end
                    local edgeOK, kind, path = pcall(edgePath, ids[edgeIndex], view.number, opts.roads, opts.rails)
                    edgeIndex = edgeIndex + 1
                    if edgeOK then
                        if kind then paths[kind][#paths[kind] + 1] = path end
                    elseif not edgeWarning then
                        edgeWarning = true
                        warn("Routes/rails incomplets (aretes ignorees) : " .. tostring(kind))
                    end
                end
                self.progress = 0.66 + 0.19 * (edgeIndex - 1) / math.max(1, #ids)
                if edgeIndex > #ids then
                    ids, pathIndex = nil, 1
                    queue("<g id='roads' fill='none' stroke='#697d89' stroke-width='1.1px'>\n")
                    advance("roads", 0.85)
                end
            elseif self.phase == "roads" or self.phase == "rails" then
                local kind = self.phase
                local last = math.min(#paths[kind], pathIndex + EDGES - 1)
                if pathIndex <= last then
                    queue(table.concat(paths[kind], "", pathIndex, last))
                    pathIndex = last + 1
                else
                    paths[kind] = nil
                    if kind == "roads" then
                        queue("</g>\n<g id='rails' fill='none' stroke='#334551' stroke-width='1.1px'>\n")
                        pathIndex = 1
                        advance("rails", 0.91)
                    else
                        queue("</g>\n")
                        paths = nil
                        advance("suffix", 0.96)
                    end
                end
            elseif self.phase == "suffix" then
                local suffix = view.suffix(copied)
                if #self.warnings > 0 then
                    local messages = {}
                    for _, warning in ipairs(self.warnings) do
                        messages[#messages + 1] = "<li>" .. view.escape(warning) .. "</li>"
                    end
                    local html = "<section id='export-warnings' role='status' style='position:fixed;bottom:1rem;left:1rem;z-index:1000;width:36rem;max-width:calc(100vw - 2rem);max-height:30vh;overflow:auto;overflow-wrap:anywhere;background:#fff3cd;color:#332701;padding:1rem;border:1px solid #947526'>"
                        .. "<h2>Avertissements export</h2><ul>" .. table.concat(messages) .. "</ul></section>"
                    local count
                    suffix, count = suffix:gsub("</[bB][oO][dD][yY]%s*>", function(tag) return html .. tag end, 1)
                    assert(count == 1, "view.suffix must close the HTML body")
                end
                queue(suffix)
                advance("flush", 0.98)
            elseif self.phase == "flush" then
                local result, message = handle:flush()
                assert(result, "flush: " .. tostring(message))
                advance("close", 0.99)
            elseif self.phase == "close" then
                local closed, message = closeHandle()
                assert(closed, "close: " .. tostring(message))
                advance("publish", 0.99)
            elseif self.phase == "publish" then
                if canRename then
                    -- Standard Lua has no atomic rename-no-replace. Check immediately
                    -- before rename, without yielding; never replace a known file.
                    if exists(target) then target = candidate(); return end
                    local result, message = rename(partial, target)
                    assert(result, "rename: " .. tostring(message))
                end
                partial = nil
                self.path, self.done = target, true
                advance("done", 1)
            else
                error("Unknown export phase: " .. tostring(self.phase))
            end
        end)
        if not success then fail(failure) end
        return self.done
    end
    return job
end

return exporter
