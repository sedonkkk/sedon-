--!nonstrict
-- Minimal Vector3 adapter for the official Luau CLI; no Roblox runtime needed.
local Vector = {}
local mt = {}
function Vector.new(x, y, z)
 return setmetatable({X=x or 0, Y=y or 0, Z=z or 0}, mt)
end
function Vector:Dot(other)
 return self.X*other.X+self.Y*other.Y+self.Z*other.Z
end
mt.__index = function(self, key)
 if key=="Magnitude" then return math.sqrt(self:Dot(self)) end
 return Vector[key]
end
mt.__add = function(a,b) return Vector.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
mt.__sub = function(a,b) return Vector.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
mt.__unm = function(a) return Vector.new(-a.X,-a.Y,-a.Z) end
mt.__mul = function(a,b)
 if type(a)=="number" then return Vector.new(a*b.X,a*b.Y,a*b.Z) end
 assert(type(b)=="number", "Vector multiplication requires a scalar")
 return Vector.new(a.X*b,a.Y*b,a.Z*b)
end
mt.__div = function(a,b) return Vector.new(a.X/b,a.Y/b,a.Z/b) end
mt.__tostring = function(a) return string.format("(%g,%g,%g)",a.X,a.Y,a.Z) end
return Vector
