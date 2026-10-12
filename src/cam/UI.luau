--!nonstrict
local Branding = if script then require(script.Parent.Branding) else require("./Branding")
local UserInputService = if game then game:GetService("UserInputService") else nil
local World = if game then game:GetService("Workspace") else nil
local UI = {}
UI.__index = UI
local WIDTH, HEIGHT = 310, 324
local PARTS = {"Head", "UpperTorso", "HumanoidRootPart"}
local NUMBERS = {
	{"CamPrediction", "Cam Prediction", "%.2f"},
	{"PredictionX", "Prediction X", "%.4f"},
	{"PredictionY", "Prediction Y", "%.4f"},
	{"Smoothness", "Smoothness", "%.3f"},
	{"Radius", "Radius", "%g"},
}

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function point(input)
	local position = input and input.Position
	if position and finite(position.X) and finite(position.Y) then return position.X, position.Y end
	return nil
end
local function contains(object, x, y)
	if not object or not x then return false end
	local position, size = object.AbsolutePosition, object.AbsoluteSize
	return x >= position.X and x <= position.X + size.X and y >= position.Y and y <= position.Y + size.Y
end

function UI:_create(className, properties, parent)
	local instance = Instance.new(className)
	table.insert(self.owned, instance)
	for key, value in pairs(properties) do instance[key] = value end
	instance.Parent = parent
	return instance
end
function UI:_connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(self.connections, connection)
	return connection
end
function UI:_label(parent, name, text, position, size, textSize, color)
	return self:_create("TextLabel", {
		Name = name, Active = false, BackgroundTransparency = 1, Text = text,
		TextColor3 = color or Branding.Colors.White, Font = Enum.Font.Gotham,
		TextSize = textSize or 12, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center, Position = position, Size = size, ZIndex = 3,
	}, parent)
end
function UI:_control(className, field, parent)
	local control = self:_create(className, {
		Name = field, Active = true, BackgroundColor3 = Branding.Colors.Input,
		BorderSizePixel = 0, Position = UDim2.fromOffset(143, 3), Size = UDim2.fromOffset(133, 25),
		Text = "", TextColor3 = Branding.Colors.White, Font = Enum.Font.Gotham,
		TextSize = 11, ZIndex = 4,
	}, parent)
	self:_create("UIStroke", {Color = Branding.Colors.Border, Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, control)
	self:_create("UICorner", {CornerRadius = UDim.new(0, 3)}, control)
	self.controls[field] = control
	return control
end
function UI:_row(index, field, title)
	local row = self:_create("Frame", {
		Name = field .. "Row", Active = false, BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 82 + (index - 1) * 32), Size = UDim2.fromOffset(278, 31), ZIndex = 3,
	}, self.panel)
	self:_label(row, "Label", title, UDim2.fromOffset(0, 0), UDim2.fromOffset(140, 31))
	return row
end
function UI:_notice(reason)
	if type(self.onNotice) == "function" then pcall(self.onNotice, tostring(reason or "Invalid value")) end
end
function UI:_change(field, value)
	if self.destroyed then return false end
	local ok, accepted, reason = pcall(self.onChange, field, value)
	if not ok then reason, accepted = accepted, false end
	if accepted == true then
		self:setValue(field, value)
		return true
	end
	self:setValue(field, self.values[field])
	self:_notice(reason)
	return false
end
function UI:setValue(field, value)
	if self.destroyed or not self.controls[field] then return false end
	self.values[field] = value
	local control = self.controls[field]
	if field == "Enabled" then
		control.Text = value == true and "ON" or "OFF"
		control.BackgroundColor3 = value == true and Branding.Colors.Neon or Branding.Colors.Input
		control.TextColor3 = value == true and Branding.Colors.White or Branding.Colors.Muted
	elseif field == "HitPart" then
		control.Text = tostring(value) .. "  ▾"
	else
		control.Text = finite(value) and string.format(self.formats[field], value) or ""
	end
	return true
end
function UI:closeDropdown()
	if not self.destroyed and self.dropdown then self.dropdown.Visible = false end
end

function UI:_fit()
	if self.destroyed then return end
	local camera = World and World.CurrentCamera
	local viewport = camera and camera.ViewportSize or self.gui.AbsoluteSize
	if not viewport or not finite(viewport.X) or not finite(viewport.Y) or viewport.X <= 0 or viewport.Y <= 0 then return end
	local scale = math.max(0.01, math.min(1, (viewport.X - 16) / WIDTH, (viewport.Y - 16) / HEIGHT))
	self.scale.Scale = scale
	local position = self.panel.Position
	local marginX, marginY = math.min(8, math.max(0, viewport.X - WIDTH * scale)), math.min(8, math.max(0, viewport.Y - HEIGHT * scale))
	self.panel.Position = UDim2.fromOffset(
		math.clamp(position.X.Offset, marginX, math.max(marginX, viewport.X - WIDTH * scale - marginX)),
		math.clamp(position.Y.Offset, marginY, math.max(marginY, viewport.Y - HEIGHT * scale - marginY))
	)
end
function UI:step(_now)
	self:_fit()
end
function UI:_bindInput()
	self:_connect(self.header.InputBegan, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local x, y = point(input)
		if not x then return end
		self:closeDropdown()
		self.drag = {input = input, touch = input.UserInputType == Enum.UserInputType.Touch,
			x = x, y = y, position = self.panel.Position}
	end)
	self:_connect(UserInputService.InputChanged, function(input)
		local drag = self.drag
		if not drag then return end
		if drag.touch then
			if input ~= drag.input then return end
		elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
		local x, y = point(input)
		if not x then return end
		self.panel.Position = UDim2.fromOffset(drag.position.X.Offset + x - drag.x, drag.position.Y.Offset + y - drag.y)
		self:_fit()
	end)
	self:_connect(UserInputService.InputEnded, function(input)
		if self.drag and (input == self.drag.input or (not self.drag.touch and input.UserInputType == Enum.UserInputType.MouseButton1)) then self.drag = nil end
	end)
	self:_connect(UserInputService.WindowFocusReleased, function() self.drag = nil; self:closeDropdown() end)
	self:_connect(UserInputService.InputBegan, function(input)
		if not self.dropdown.Visible then return end
		if input.KeyCode == Enum.KeyCode.Escape then self:closeDropdown(); return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local x, y = point(input)
		if x and not contains(self.dropdown, x, y) and not contains(self.controls.HitPart, x, y) then self:closeDropdown() end
	end)
end

function UI.new(playerGui, config, onChange, onNotice)
	assert(playerGui, "SEDWARE Cam Lock requires PlayerGui")
	assert(type(config) == "table" and type(onChange) == "function", "SEDWARE Cam Lock UI requires validated config and onChange")
	local self = setmetatable({config = config, onChange = onChange, onNotice = onNotice,
		values = {}, controls = {}, formats = {}, hitPartOptions = {}, owned = {}, connections = {}, destroyed = false}, UI)
	local ok, problem = xpcall(function()
		local colors = Branding.Colors
		self.gui = self:_create("ScreenGui", {
			Name = "SedwareCamLock_UI", ResetOnSpawn = false, IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 41,
		}, playerGui)
		self.panel = self:_create("Frame", {
			Name = "CamLockPanel", Active = true, BackgroundColor3 = colors.Background, BorderSizePixel = 0,
			Position = UDim2.fromOffset(24, 110), Size = UDim2.fromOffset(WIDTH, HEIGHT), ZIndex = 2,
		}, self.gui)
		self.scale = self:_create("UIScale", {Scale = 1}, self.panel)
		self:_create("UIStroke", {Color = colors.Border, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, self.panel)
		self:_create("UICorner", {CornerRadius = UDim.new(0, 4)}, self.panel)
		self.header = self:_create("Frame", {
			Name = "Header", Active = true, BackgroundColor3 = colors.Surface, BorderSizePixel = 0,
			Position = UDim2.fromOffset(1, 1), Size = UDim2.fromOffset(WIDTH - 2, 49), ZIndex = 3,
		}, self.panel)
		self.logo = Branding.addLogo(self.header, function(...) return self:_create(...) end)
		self.title = self:_label(self.header, "Title", Branding.Title, UDim2.fromOffset(51, 6), UDim2.fromOffset(194, 22), 17)
		self.title.Font = Enum.Font.GothamBold
		self.subtitle = self:_label(self.header, "Subtitle", Branding.Subtitle, UDim2.fromOffset(52, 29), UDim2.fromOffset(170, 14), 9, colors.Pink)
		self.version = self:_label(self.header, "Version", Branding.Version, UDim2.fromOffset(270, 15), UDim2.fromOffset(26, 17), 10, colors.Muted)
		self:_create("Frame", {Name = "PinkAccent", Active = false, BackgroundColor3 = colors.Neon, BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 50), Size = UDim2.fromOffset(WIDTH, 2), ZIndex = 3}, self.panel)
		self.mainLabel = self:_label(self.panel, "MainLabel", "MAIN", UDim2.fromOffset(16, 57), UDim2.fromOffset(278, 18), 10, colors.Pink)
		self.mainLabel.Font = Enum.Font.GothamBold
		local enable = self:_control("TextButton", "Enabled", self:_row(1, "Enabled", "Enable"))
		enable.AutoButtonColor = false
		self:_connect(enable.Activated, function() self:_change("Enabled", self.values.Enabled ~= true) end)
		local partRow = self:_row(2, "HitPart", "Hit Part")
		local part = self:_control("TextButton", "HitPart", partRow)
		part.AutoButtonColor = false
		self.dropdown = self:_create("Frame", {
			Name = "HitPartOptions", Active = true, BackgroundColor3 = colors.Surface, BorderSizePixel = 0,
			Position = UDim2.fromOffset(143, 31), Size = UDim2.fromOffset(133, 87), Visible = false, ZIndex = 20,
		}, partRow)
		self:_create("UIStroke", {Color = colors.Pink, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, self.dropdown)
		for index, value in ipairs(PARTS) do
			local choice = self:_create("TextButton", {
				Name = value, Active = true, AutoButtonColor = true, BackgroundColor3 = colors.Surface,
				BorderSizePixel = 0, Text = value, TextColor3 = colors.White, Font = Enum.Font.Gotham,
				TextSize = 10, Position = UDim2.fromOffset(2, 2 + (index - 1) * 28), Size = UDim2.fromOffset(129, 27), ZIndex = 21,
			}, self.dropdown)
			self.hitPartOptions[value] = choice
			self:_connect(choice.Activated, function() self:closeDropdown(); self:_change("HitPart", value) end)
		end
		self:_connect(part.Activated, function() self.dropdown.Visible = not self.dropdown.Visible end)
		for index, entry in ipairs(NUMBERS) do
			local field, title, format = entry[1], entry[2], entry[3]
			self.formats[field] = format
			local input = self:_control("TextBox", field, self:_row(index + 2, field, title))
			input.ClearTextOnFocus = false
			self:_connect(input.FocusLost, function()
				local value = tonumber(input.Text)
				if not finite(value) then
					self:setValue(field, self.values[field]); self:_notice("Enter a finite number")
				else self:_change(field, value) end
			end)
		end
		for field in pairs(self.controls) do self:setValue(field, config[field]) end
		self:_bindInput()
		self:_fit()
	end, function(err)
		return if debug and type(debug.traceback) == "function" then debug.traceback(tostring(err), 2) else tostring(err)
	end)
	if not ok then self:destroy(); error("SEDWARE Cam Lock UI: " .. tostring(problem), 2) end
	return self
end

function UI:destroy()
	if self.destroyed then return end
	self.destroyed, self.drag = true, nil
	for _, connection in ipairs(self.connections) do pcall(function() connection:Disconnect() end) end
	table.clear(self.connections)
	for index = #self.owned, 1, -1 do pcall(function() self.owned[index]:Destroy() end) end
	table.clear(self.owned)
end

return UI
