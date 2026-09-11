-- Pure map geometry; screen coordinates are local to the map content rectangle.
local M = {}

function M.view(bounds, width, height, zoom, cx, cy)
    local scale = math.min((width - 24) / (bounds.maxX - bounds.minX),
        (height - 24) / (bounds.maxY - bounds.minY)) * zoom
    local function centre(value, low, high, extent)
        if extent * 2 >= high - low then return (low + high) / 2 end
        return math.max(low + extent, math.min(high - extent, value or (low + high) / 2))
    end
    return { width = width, height = height, scale = scale,
        cx = centre(cx, bounds.minX, bounds.maxX, width / (2 * scale)),
        cy = centre(cy, bounds.minY, bounds.maxY, height / (2 * scale)) }
end

function M.project(view, x, y)
    return view.width / 2 + (x - view.cx) * view.scale,
        view.height / 2 - (y - view.cy) * view.scale
end

function M.unproject(view, x, y)
    return view.cx + (x - view.width / 2) / view.scale,
        view.cy - (y - view.height / 2) / view.scale
end

-- Liang-Barsky clipping also handles circles whose centres are off-screen.
function M.clip(x0, y0, x1, y1, width, height)
    local dx, dy = x1 - x0, y1 - y0
    local low, high = 0, 1
    local p, q = { -dx, dx, -dy, dy }, { x0, width - x0, y0, height - y0 }
    for i = 1, 4 do
        if p[i] == 0 then
            if q[i] < 0 then return nil end
        else
            local t = q[i] / p[i]
            if p[i] < 0 then low = math.max(low, t) else high = math.min(high, t) end
            if low > high then return nil end
        end
    end
    return x0 + low * dx, y0 + low * dy, x0 + high * dx, y0 + high * dy
end

function M.circle(line, x, y, radius)
    local count = math.max(20, math.min(128, math.ceil(radius / 3)))
    local px, py = x + radius, y
    for i = 1, count do
        local angle = i * 2 * math.pi / count
        local nx, ny = x + math.cos(angle) * radius, y + math.sin(angle) * radius
        line(px, py, nx, ny)
        px, py = nx, ny
    end
end

function M.marker(line, kind, x, y, size)
    if kind == "ANTENNA" then
        M.circle(line, x, y, size)
    elseif kind == "NRA" then
        line(x - size, y - size, x + size, y - size)
        line(x + size, y - size, x + size, y + size)
        line(x + size, y + size, x - size, y + size)
        line(x - size, y + size, x - size, y - size)
    elseif kind == "NRO" then
        line(x, y - size, x + size, y + size)
        line(x + size, y + size, x - size, y + size)
        line(x - size, y + size, x, y - size)
    else
        line(x - size, y, x + size, y)
        line(x, y - size, x, y + size)
    end
end

function M.hitTest(items, view, x, y, radius)
    local best, distance = nil, radius * radius
    for _, item in ipairs(items) do
        local px, py = M.project(view, item.x, item.y)
        local d = (px - x) ^ 2 + (py - y) ^ 2
        if d <= distance then best, distance = item, d end
    end
    return best
end

return M
