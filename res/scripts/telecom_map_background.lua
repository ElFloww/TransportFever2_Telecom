-- Optional cartographic context. Work is spread across GUI frames and cached.
local M = {}

function M.new(bounds)
    local spanX, spanY = bounds.maxX - bounds.minX, bounds.maxY - bounds.minY
    local columns = math.max(8, math.floor(96 * math.min(1, spanX / spanY)))
    local rows = math.max(8, math.floor(96 * math.min(1, spanY / spanX)))
    local self = { terrain = {}, roads = {}, rails = {}, warnings = {}, done = false }
    local cellSize = math.max(256, math.max(spanX, spanY) / 32)
    local indexes = { roads = {}, rails = {} }
    local dx, dy = spanX / columns, spanY / rows
    local cell, edgeIndex, edges = 0, 1, nil
    local waterLevel = 0
    local previousRow = {}
    local function warn(message)
        self.warnings[#self.warnings + 1] = message
        print("[Telecom map] " .. message)
    end
    local ok, err = pcall(function()
        local terrain = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.TERRAIN)
        waterLevel = assert(terrain and terrain.waterLevel, "waterLevel unavailable")
    end)
    if not ok then
        cell = columns * rows
        warn("Relief indisponible : " .. tostring(err))
    end

    function self:segments(kind, minX, minY, maxX, maxY)
        local x0, y0 = math.floor(minX / cellSize), math.floor(minY / cellSize)
        local x1, y1 = math.floor(maxX / cellSize), math.floor(maxY / cellSize)
        local x, y, index, seen = x0, y0, 0, {}
        return function()
            while x <= x1 do
                local bucket = indexes[kind][x .. ":" .. y] or {}
                index = index + 1
                local segment = bucket[index]
                if segment then
                    if not seen[segment] then seen[segment] = true; return segment end
                else
                    index, y = 0, y + 1
                    if y > y1 then x, y = x + 1, y0 end
                end
            end
        end
    end

    function self:step()
        if self.done then return false end
        local success, failure = pcall(function()
            if cell < columns * rows then
                for _ = 1, 128 do
                    if cell >= columns * rows then break end
                    local col, row = cell % columns, math.floor(cell / columns)
                    local x, y = bounds.minX + col * dx, bounds.minY + row * dy
                    local height = api.engine.terrain.getHeightAt(api.type.Vec2f.new(x + dx / 2, y + dy / 2))
                    local band = height <= waterLevel and "water"
                        or height < waterLevel + 80 and "low"
                        or height < waterLevel + 200 and "hill" or "high"
                    -- Water strokes and elevation boundaries, not a screenshot of the terrain.
                    if band == "water" then
                        self.terrain[#self.terrain + 1] = { x, y + dy / 2, x + dx, y + dy / 2, band }
                    else
                        if row > 0 and previousRow[col] ~= band then
                            self.terrain[#self.terrain + 1] = { x, y, x + dx, y, band }
                        end
                        if col > 0 and previousRow[col - 1] ~= band then
                            self.terrain[#self.terrain + 1] = { x, y, x, y + dy, band }
                        end
                    end
                    previousRow[col] = band
                    cell = cell + 1
                end
                self.progress = math.floor(100 * cell / (columns * rows))
                return
            end
            if not edges then
                edges = {}
                api.engine.forEachEntityWithComponent(function(id)
                    edges[#edges + 1] = id
                end, api.type.ComponentType.BASE_EDGE)
            end
            for _ = 1, 128 do
                local id = edges[edgeIndex]
                if not id then self.done = true; return end
                edgeIndex = edgeIndex + 1
                if api.engine.entityExists(id) then
                    local edge = api.engine.getComponent(id, api.type.ComponentType.BASE_EDGE)
                    if edge and api.engine.entityExists(edge.node0) and api.engine.entityExists(edge.node1) then
                        local a = api.engine.getComponent(edge.node0, api.type.ComponentType.BASE_NODE)
                        local b = api.engine.getComponent(edge.node1, api.type.ComponentType.BASE_NODE)
                        if a and b then
                            local kind = api.engine.getComponent(id, api.type.ComponentType.BASE_EDGE_TRACK)
                                and "rails" or "roads"
                            local target = self[kind]
                            local p, q, t0, t1 = a.position, b.position, edge.tangent0, edge.tangent1
                            local px, py = p.x, p.y
                            -- Cubic Hermite interpolation preserves curved roads and tracks.
                            for i = 1, 4 do
                                local t = i / 4
                                local h0, h1 = 2 * t^3 - 3 * t^2 + 1, -2 * t^3 + 3 * t^2
                                local h2, h3 = t^3 - 2 * t^2 + t, t^3 - t^2
                                local x = h0 * p.x + h1 * q.x + h2 * t0.x + h3 * t1.x
                                local y = h0 * p.y + h1 * q.y + h2 * t0.y + h3 * t1.y
                                local segment = { px, py, x, y }
                                target[#target + 1] = segment
                                for ix = math.floor(math.min(px, x) / cellSize), math.floor(math.max(px, x) / cellSize) do
                                    for iy = math.floor(math.min(py, y) / cellSize), math.floor(math.max(py, y) / cellSize) do
                                        local key = ix .. ":" .. iy
                                        local bucket = indexes[kind][key] or {}
                                        indexes[kind][key] = bucket
                                        bucket[#bucket + 1] = segment
                                    end
                                end
                                px, py = x, y
                            end
                        end
                    end
                end
            end
        end)
        if not success then
            if cell < columns * rows then
                cell = columns * rows
                warn("Relief incomplet : " .. tostring(failure))
            else
                self.done = true
                warn("Routes/rails incomplets : " .. tostring(failure))
            end
        end
        return self.done
    end
    return self
end

return M
