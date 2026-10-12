--!nonstrict
-- Display-only overlay: the dot receives an observed position, never a prediction.
-- All controls remain with Roblox; there are no buttons or input connections.
local Overlay = {}
Overlay.__index = Overlay
local FADE_SECONDS = 0.18

local function create(self, className, properties, parent)
	local object = Instance.new(className)
	-- Track before property assignment so construction failures leave no orphans.
	table.insert(self.owned, object)
	for key, value in pairs(properties) do object[key] = value end
	object.Parent = parent
	return object
end
local function finite(number)
	return type(number) == "number" and number == number and math.abs(number) < math.huge
end
local function xy(point)
	if point == nil then return nil end
	local ok, x, y = pcall(function() return point.X, point.Y end)
	if ok and finite(x) and finite(y) then return x, y end
	return nil
end

function Overlay.new(playerGui, config)
	local self = setmetatable({ config = config or {}, owned = {}, destroyed = false }, Overlay)
	local ok, problem = pcall(function()
		local settings = self.config
		local hotPink, white = Color3.fromRGB(255, 105, 180), Color3.fromRGB(255, 255, 255)
		self.gui = create(self, "ScreenGui", {
			Name = "PinkDotLock", ResetOnSpawn = false, IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 40,
		}, playerGui)
		self.dot = create(self, "Frame", {
			Name = "PinkDot", Active = false, BackgroundColor3 = settings.DotColor or hotPink,
			BackgroundTransparency = settings.DotTransparency or 0, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(settings.DotSize or 6, settings.DotSize or 6),
			Visible = false, ZIndex = 3,
		}, self.gui)
		create(self, "UICorner", { CornerRadius = UDim.new(1, 0) }, self.dot)
		if settings.DotOutline ~= false then
			create(self, "UIStroke", { Color = settings.DotOutlineColor or white,
				Thickness = 1, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}, self.dot)
		end
		self.toast = create(self, "CanvasGroup", {
			Name = "Notification", Active = false, BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.25, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28),
			Size = UDim2.new(0.85, 0, 0, 72), GroupTransparency = 1, Visible = false,
			ZIndex = 5,
		}, self.gui)
		create(self, "UISizeConstraint", { MaxSize = Vector2.new(360, 72) }, self.toast)
		create(self, "UICorner", { CornerRadius = UDim.new(0, 9) }, self.toast)
		local accent = create(self, "Frame", {
			Name = "PinkAccent", Active = false, BackgroundColor3 = hotPink,
			BorderSizePixel = 0, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0, 4, 1, 0),
			ZIndex = 6,
		}, self.toast)
		create(self, "UICorner", { CornerRadius = UDim.new(0, 2) }, accent)
		self.title = create(self, "TextLabel", {
			Name = "Title", Active = false, BackgroundTransparency = 1, Text = "",
			TextColor3 = white, Font = Enum.Font.GothamBold, TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(17, 9), Size = UDim2.new(1, -32, 0, 28), ZIndex = 6,
		}, self.toast)
		self.body = create(self, "TextLabel", {
			Name = "Body", Active = false, BackgroundTransparency = 1, Text = "",
			TextColor3 = white, Font = Enum.Font.Gotham, TextSize = 11,
			TextTransparency = 0.12, TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = true,
			Position = UDim2.fromOffset(17, 37), Size = UDim2.new(1, -32, 0, 25), ZIndex = 6,
		}, self.toast)
	end)
	if not ok then
		self:destroy()
		error("PINK DOT LOCK overlay: " .. tostring(problem), 2)
	end
	return self
end

function Overlay:setDot(viewportPoint, onScreen, inset)
	if self.destroyed then return false end
	local x, y = xy(viewportPoint)
	if not onScreen or self.config.ShowDot == false or not x then self:hideDot(); return false end
	local insetX, insetY = xy(inset)
	-- WorldToViewportPoint omits the GUI inset; this full-screen GUI includes it.
	self.dot.Position = UDim2.fromOffset(x + (insetX or 0), y + (insetY or 0))
	self.dot.Visible = true
	return true
end

function Overlay:hideDot()
	if not self.destroyed then self.dot.Visible = false end
end

function Overlay:notify(message, now, duration, subtitle)
	if self.destroyed then return false end
	if self.config.ShowNotifications == false then
		self.toast.Visible = false
		self.noticeStart = nil
		return false
	end
	if not finite(now) then return false end
	duration = duration or self.config.NotificationDuration or 2
	if not finite(duration) or duration <= 0 then return false end
	self.title.Text = tostring(message or "")
	self.body.Text = subtitle and tostring(subtitle) or ""
	self.body.Visible = subtitle ~= nil and subtitle ~= ""
	self.title.Position = UDim2.fromOffset(17, self.body.Visible and 9 or 0)
	self.title.Size = UDim2.new(1, -32, 0, self.body.Visible and 28 or 72)
	self.noticeStart, self.noticeDuration = now, duration
	self.toast.GroupTransparency = 1
	self.toast.Position = UDim2.new(0.5, 0, 1, -20)
	self.toast.Visible = true
	return true
end

function Overlay:step(now)
	if self.destroyed or not self.noticeStart or not finite(now) then return end
	if self.config.ShowNotifications == false then
		self.toast.Visible = false
		self.noticeStart = nil
		return
	end
	local elapsed = math.max(0, now - self.noticeStart)
	if elapsed >= self.noticeDuration then
		self.toast.Visible = false
		self.toast.GroupTransparency = 1
		self.noticeStart = nil
		return
	end
	local fade = math.min(FADE_SECONDS, self.noticeDuration / 2)
	local visibility = math.clamp(math.min(elapsed / fade, (self.noticeDuration - elapsed) / fade), 0, 1)
	-- Smoothstep is time-based and creates no tweens or scheduled callbacks.
	visibility = visibility * visibility * (3 - 2 * visibility)
	self.toast.GroupTransparency = 1 - visibility
	self.toast.Position = UDim2.new(0.5, 0, 1, -20 - 8 * visibility)
end

function Overlay:destroy()
	if self.destroyed then return end
	self.destroyed = true
	self.noticeStart = nil
	for index = #self.owned, 1, -1 do
		pcall(function() self.owned[index]:Destroy() end)
	end
	table.clear(self.owned)
end

return Overlay
