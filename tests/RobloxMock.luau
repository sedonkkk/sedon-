--!nonstrict
-- Minimal event/lifecycle doubles, used with the REAL bundled Interface source.
-- This is not a Roblox engine, renderer, physics or replication simulator.
local Vector3 = require("./Vector")
local Mock = {}

function Mock.new()
	local instances, connections = {}, {}
	local function signal()
		local self = {listeners = {}}
		function self:Connect(callback)
			local connection = {Connected = true, callback = callback}
			function connection:Disconnect() self.Connected = false end
			table.insert(self.listeners, connection)
			table.insert(connections, connection)
			return connection
		end
		function self:Once(callback)
			local connection
			connection = self:Connect(function(...)
				connection:Disconnect()
				callback(...)
			end)
			return connection
		end
		function self:Fire(...)
			local snapshot = table.clone(self.listeners)
			for _, connection in ipairs(snapshot) do
				if connection.Connected then connection.callback(...) end
			end
		end
		function self:DisconnectAll()
			for _, connection in ipairs(self.listeners) do connection:Disconnect() end
		end
		return self
	end
	local Vector2 = {}
	local vector2Meta = {}
	function Vector2.new(x, y) return setmetatable({X = x or 0, Y = y or 0}, vector2Meta) end
	vector2Meta.__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end
	vector2Meta.__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end
	vector2Meta.__mul = function(a, b)
		if type(a) == "number" then return Vector2.new(a * b.X, a * b.Y) end
		return Vector2.new(a.X * b, a.Y * b)
	end
	vector2Meta.__div = function(a, b) return Vector2.new(a.X / b, a.Y / b) end
	vector2Meta.__index = function(v, key)
		if key == "Magnitude" then return math.sqrt(v.X ^ 2 + v.Y ^ 2) end
		return Vector2[key]
	end
	local UDim = {}
	function UDim.new(scale, offset) return {Scale = scale or 0, Offset = offset or 0} end
	local UDim2 = {}
	function UDim2.new(xScale, xOffset, yScale, yOffset)
		return {X = UDim.new(xScale, xOffset), Y = UDim.new(yScale, yOffset)}
	end
	function UDim2.fromOffset(x, y) return UDim2.new(0, x, 0, y) end
	function UDim2.fromScale(x, y) return UDim2.new(x, 0, y, 0) end
	local Color3 = {}
	function Color3.new(r, g, b) return {R = r or 0, G = g or 0, B = b or 0} end
	function Color3.fromRGB(r, g, b) return Color3.new(r / 255, g / 255, b / 255) end
	function Color3.fromHSV(h, s, v) return {H = h, S = s, V = v} end
	local Enum = setmetatable({}, {__index = function(enum, category)
		local values = setmetatable({}, {__index = function(group, name)
			local value = {Name = name, EnumType = category}
			rawset(group, name, value)
			return value
		end})
		rawset(enum, category, values)
		return values
	end})
	local SIGNAL_PROPERTIES = {
		Activated = true, MouseButton1Click = true, InputBegan = true, InputChanged = true,
		InputEnded = true, FocusLost = true, Focused = true, MouseEnter = true, MouseLeave = true,
		Changed = true, Destroying = true, AncestryChanged = true, Event = true,
		CharacterAdded = true, CharacterRemoving = true, PlayerAdded = true, PlayerRemoving = true,
		WindowFocusReleased = true,
	}
	local Node = {}
	local nodeMeta = {}
	local function detach(self)
		local parent = self._props.Parent
		if parent then
			for index, child in ipairs(parent._children) do
				if child == self then table.remove(parent._children, index); break end
			end
		end
	end
	function Node:GetChildren() return table.clone(self._children) end
	function Node:GetDescendants()
		local found = {}
		local function visit(node)
			for _, child in ipairs(node._children) do table.insert(found, child); visit(child) end
		end
		visit(self)
		return found
	end
	function Node:FindFirstChild(name, recursive)
		for _, child in ipairs(self._children) do if child.Name == name then return child end end
		if recursive then
			for _, child in ipairs(self:GetDescendants()) do if child.Name == name then return child end end
		end
		return nil
	end
	function Node:WaitForChild(name)
		local child = self:FindFirstChild(name)
		assert(child, "mock missing child " .. tostring(name))
		return child
	end
	function Node:IsA(className)
		if self.ClassName == className or className == "Instance" then return true end
		if className == "GuiObject" then
			return self.ClassName == "Frame" or self.ClassName == "TextLabel" or self.ClassName == "TextButton"
				or self.ClassName == "TextBox" or self.ClassName == "ScrollingFrame"
		end
		return false
	end
	function Node:GetPropertyChangedSignal(key)
		if not self._propertySignals[key] then self._propertySignals[key] = signal() end
		return self._propertySignals[key]
	end
	function Node:IsFocused() return self._focused == true end
	function Node:CaptureFocus() self._focused = true; self.Focused:Fire() end
	function Node:ReleaseFocus(enterPressed)
		self._focused = false
		self.FocusLost:Fire(enterPressed == true)
	end
	function Node:Fire(...) self.Event:Fire(...) end
	function Node:GetAttribute(key) return self._attributes[key] end
	function Node:SetAttribute(key, value) self._attributes[key] = value end
	function Node:Destroy()
		if self._destroyed then return end
		self.Destroying:Fire()
		self._destroyed = true
		for _, child in ipairs(self:GetChildren()) do child:Destroy() end
		for _, event in pairs(self._signals) do event:DisconnectAll() end
		for _, event in pairs(self._propertySignals) do event:DisconnectAll() end
		detach(self)
		self._props.Parent = nil
	end
	local Instance = {}
	function Instance.new(className)
		local node = setmetatable({_props = {ClassName = className, Name = className,
			Visible = true, Enabled = true, Scale = 1, Size = UDim2.fromOffset(0, 0),
			Position = UDim2.fromOffset(0, 0), CanvasPosition = Vector2.new(0, 0), Text = ""}, _children = {}, _signals = {},
			_propertySignals = {}, _attributes = {}, _destroyed = false}, nodeMeta)
		table.insert(instances, node)
		return node
	end
	local function geometry(node, property)
		local parent = node.Parent
		local parentSize = parent and parent.AbsoluteSize or Vector2.new(1280, 720)
		local value = node[property]
		local result = Vector2.new(parentSize.X * value.X.Scale + value.X.Offset,
			parentSize.Y * value.Y.Scale + value.Y.Offset)
		if property == "Position" then
			local parentPosition = parent and parent.AbsolutePosition or Vector2.new(0, 0)
			return parentPosition + result
		end
		for _, child in ipairs(node._children) do
			if child.ClassName == "UIScale" then return result * child.Scale end
		end
		return result
	end
	nodeMeta.__index = function(node, key)
		if Node[key] then return Node[key] end
		if SIGNAL_PROPERTIES[key] then
			if not node._signals[key] then node._signals[key] = signal() end
			return node._signals[key]
		end
		if key == "AbsoluteSize" then
			if node.ClassName == "ScreenGui" then return Vector2.new(1280, 720) end
			return geometry(node, "Size")
		end
		if key == "AbsolutePosition" then return geometry(node, "Position") end
		return node._props[key]
	end
	nodeMeta.__newindex = function(node, key, value)
		if string.sub(key, 1, 1) == "_" then rawset(node, key, value); return end
		if key == "Parent" then
			detach(node)
			if value then table.insert(value._children, node) end
		end
		local old = node._props[key]
		node._props[key] = value
		if old ~= value and node._propertySignals[key] then node._propertySignals[key]:Fire() end
	end
	local playerGui = Instance.new("PlayerGui")
	playerGui.Name = "PlayerGui"
	local player = Instance.new("Player")
	player.Name = "LocalPlayer"
	playerGui.Parent = player
	local camera = Instance.new("Camera")
	camera.ViewportSize = Vector2.new(1280, 720)
	local world = Instance.new("Workspace")
	world.CurrentCamera = camera
	local clock = 1
	function world:GetServerTimeNow() return clock end
	function world:Raycast(_origin, _direction, _params) return nil end
	local inputService = Instance.new("UserInputService")
	inputService.TouchEnabled = false
	inputService.KeyboardEnabled = true
	inputService.MouseEnabled = true
	local pointer = Vector2.new(10, 10)
	function inputService:GetMouseLocation() return pointer end
	function inputService:GetFocusedTextBox()
		for _, node in ipairs(instances) do if node.ClassName == "TextBox" and node:IsFocused() then return node end end
		return nil
	end
	function inputService:IsKeyDown(_key) return false end
	local players = Instance.new("Players")
	players.LocalPlayer = player
	function players:GetPlayers() return {player} end
	local runService = {RenderStepped = signal(), Heartbeat = signal()}
	function runService:IsClient() return true end
	function runService:IsStudio() return true end
	local http = {}
	local jsonObjects, jsonCounter = {}, 0
	function http:JSONEncode(object)
		-- A deterministic transport double, sufficient to check the UI hands a
		-- valid envelope to serialization and round-trips it through callbacks.
		jsonCounter += 1
		local encoded = "mock-json:" .. tostring(jsonCounter)
		jsonObjects[encoded] = object
		return encoded
	end
	function http:JSONDecode(encoded)
		assert(jsonObjects[encoded], "mock invalid JSON")
		return jsonObjects[encoded]
	end
	local tweenService = {}
	function tweenService:Create(node, _info, properties)
		return {Completed = signal(), Play = function()
			for key, value in pairs(properties) do node[key] = value end
		end, Cancel = function() end}
	end
	local services = {Players = players, UserInputService = inputService, RunService = runService,
		HttpService = http, TweenService = tweenService, Workspace = world, GuiService = {}}
	function services.GuiService:GetGuiInset() return Vector2.new(0, 0), Vector2.new(0, 0) end
	local game = {PlaceId = 0}
	function game:GetService(name) assert(services[name], "mock missing service " .. name); return services[name] end
	function game:IsLoaded() return true end
	local env = setmetatable({game = game, workspace = world, Vector2 = Vector2, Vector3 = Vector3,
		UDim = UDim, UDim2 = UDim2, Color3 = Color3, Enum = Enum, Instance = Instance,
		DHPREDICTION_NO_AUTOSTART = true,
		CFrame = {lookAt = function(position, target)
			-- Constructor double only. These tests never emulate camera physics.
			local direction = target - position
			if direction.Magnitude > 0 then direction /= direction.Magnitude end
			return {Position = position, LookVector = direction}
		end},
		RaycastParams = {new = function() return {} end},
		TweenInfo = {new = function(...) return {...} end},
		Random = {new = function()
			return {NextNumber = function(_self, low, high)
				if low == nil then return 0.5 end
				return (low + high) / 2
			end}
		end},
		task = {defer = function(callback, ...) return callback(...) end,
			spawn = function(callback, ...) return callback(...) end,
			delay = function(_delay, callback, ...) return callback(...) end,
			wait = function() return 0 end},
		warn = print}, {__index = getfenv()})
	local result = {env = env, services = services, instances = instances, connections = connections,
		Vector2 = Vector2, playerGui = playerGui, camera = camera, world = world, signal = signal}
	function result:countConnections()
		local count = 0
		for _, connection in ipairs(connections) do if connection.Connected then count += 1 end end
		return count
	end
	function result:find(nameOrText, root)
		root = root or playerGui
		for _, node in ipairs(root:GetDescendants()) do
			if node.Name == nameOrText or node.Text == nameOrText then return node end
		end
		return nil
	end
	function result:setPointer(x, y) pointer = Vector2.new(x, y) end
	function result:setTime(seconds) clock = seconds end
	function result:input(kind, x, y, key)
		return {UserInputType = Enum.UserInputType[kind], Position = Vector3.new(x or 0, y or 0, 0),
			KeyCode = Enum.KeyCode[key or "Unknown"], UserInputState = Enum.UserInputState.Begin, Changed = signal()}
	end
	return result
end

return Mock
