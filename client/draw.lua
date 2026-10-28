-- See-through boxes in a dyno's frame, see shared/geometry.lua. Callers draw them every frame, nothing loops here
DynoDraw = {}

-- Metres off the floor, so they do not flicker in it
local tintLift = 0.02
local lineLift = 0.03

---@alias DynoColour {[1]: integer, [2]: integer, [3]: integer, [4]: integer}

---@class DynoBoxColours
---@field floor DynoColour @ The tint on the floor under it
---@field side DynoColour
---@field edge DynoColour

---@param a vector3
---@param b vector3
---@param c vector3
---@param d vector3
---@param colour DynoColour
function DynoDraw.quad(a, b, c, d, colour)
    local red, green, blue, alpha = colour[1], colour[2], colour[3], colour[4]

    -- Both faces, since a poly is only seen from one side
    DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, red, green, blue, alpha)
    DrawPoly(a.x, a.y, a.z, c.x, c.y, c.z, d.x, d.y, d.z, red, green, blue, alpha)
    DrawPoly(c.x, c.y, c.z, b.x, b.y, b.z, a.x, a.y, a.z, red, green, blue, alpha)
    DrawPoly(d.x, d.y, d.z, c.x, c.y, c.z, a.x, a.y, a.z, red, green, blue, alpha)
end

---@param a vector3
---@param b vector3
---@param colour DynoColour
function DynoDraw.line(a, b, colour)
    DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, colour[1], colour[2], colour[3], colour[4])
end

-- A box standing on the floor of a dyno's frame, from one corner to the other
---@param frame {coords: vector3, heading: number}
---@param min vector2
---@param max vector2
---@param height number @ Metres
---@param colours DynoBoxColours
function DynoDraw.box(frame, min, max, height, colours)
    ---@param z number
    ---@return vector3 a @ The corners round it at that height
    ---@return vector3 b
    ---@return vector3 c
    ---@return vector3 d
    local function getCorners(z)
        local toWorld = DynoGeometry.toWorld

        return toWorld(frame, vec3(min.x, min.y, z)), toWorld(frame, vec3(max.x, min.y, z)), toWorld(frame, vec3(max.x, max.y, z)), toWorld(frame, vec3(min.x, max.y, z))
    end

    local tintA, tintB, tintC, tintD = getCorners(tintLift)
    local a, b, c, d = getCorners(lineLift)
    local e, f, g, h = getCorners(height)

    DynoDraw.quad(tintA, tintB, tintC, tintD, colours.floor)

    for _, side in ipairs({{a, b, f, e}, {b, c, g, f}, {c, d, h, g}, {d, a, e, h}, {e, f, g, h}}) do
        DynoDraw.quad(side[1], side[2], side[3], side[4], colours.side)
    end

    for _, edge in ipairs({{a, b}, {b, c}, {c, d}, {d, a}, {a, e}, {b, f}, {c, g}, {d, h}, {e, f}, {f, g}, {g, h}, {h, e}}) do
        DynoDraw.line(edge[1], edge[2], colours.edge)
    end
end