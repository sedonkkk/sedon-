--!nonstrict
-- Native API doubles for the REAL PinkDotLock bundle.
-- These verify events, lifecycle and given projection coordinates only; they
-- do not constitute Roblox engine, render, physics or third-party validation.
local Vector3 = {}
local vector3Meta = {}
function Vector3.new(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, vector3Meta) end
function Vector3:Dot(other) return self.X * other.X + self.Y * other.Y + self.Z * other.Z end
function Vector3:Cross(other) return Vector3.new(self.Y * other.Z - self.Z * other.Y, self.Z * other.X - self.X * other.Z, self.X * other.Y - self.Y * other.X) end
function Vector3:Lerp(other, alpha) return self + (other - self) * alpha end
vector3Meta.__index = function(value, key)
	if key == "Magnitude" then return math.sqrt(value:Dot(value)) end
	if key == "Unit" then return if value.Magnitude > 0 then value / value.Magnitude else Vector3.new(0, 0, 0) end
	return Vector3[key]
end
vector3Meta.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
vector3Meta.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
vector3Meta.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
vector3Meta.__mul = function(a, b)
	if type(a) == "number" then return Vector3.new(a * b.X, a * b.Y, a * b.Z) end
	return Vector3.new(a.X * b, a.Y * b, a.Z * b)
end
vector3Meta.__div = function(a, b) return Vector3.new(a.X / b, a.Y / b, a.Z / b) end
Vector3.zero, Vector3.xAxis, Vector3.yAxis = Vector3.new(), Vector3.new(1, 0, 0), Vector3.new(0, 1, 0)
local Mock = {}
-- Kept independent of RobloxMock so DH PREDICTION LAB tests remain unchanged.

function Mock.new()
	local instances, connections = {}, {}
	local counters = {candidateScans = 0, projections = 0, raycasts = 0, cameraWrites = 0, mouseWrites = 0}
	local clock, scheduled = 1, {}
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
	function Color3.new(r, g, b) return {R = r or 0, G = g or 0, B = b or 0, _mockType = "Color3"} end
	function Color3.fromRGB(r, g, b) return Color3.new(r / 255, g / 255, b / 255) end
	function Color3.fromHSV(h, s, v) return {H = h, S = s, V = v} end
	local Enum = setmetatable({}, {__index = function(enum, category)
		local values = setmetatable({}, {__tostring = function() return "Enum." .. category end, __index = function(group, name)
			local value = setmetatable({Name = name, EnumType = group, _mockType = "EnumItem"},
				{__tostring=function() return "Enum."..category.."."..name end})
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
		WindowFocusReleased = true, Died = true, HealthChanged = true,
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
		if className == "BasePart" then
			return self.ClassName == "Part" or self.ClassName == "MeshPart" or self.ClassName == "SpawnLocation"
		end
		if className == "GuiObject" then
			return self.ClassName == "Frame" or self.ClassName == "TextLabel" or self.ClassName == "TextButton"
				or self.ClassName == "TextBox" or self.ClassName == "ScrollingFrame" or self.ClassName == "CanvasGroup"
		end
		return false
	end
	function Node:FindFirstChildOfClass(className)
		for _, child in ipairs(self._children) do if child:IsA(className) then return child end end
		return nil
	end
	function Node:IsDescendantOf(ancestor)
		local node = self.Parent
		while node do if node == ancestor then return true end; node = node.Parent end
		return false
	end
	function Node:GetState() return self._props.HumanoidState or Enum.HumanoidStateType.Running end
	function Node:ChangeState(state) self._props.HumanoidState = state end
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
		self.Parent = nil
		for _, child in ipairs(self:GetChildren()) do child:Destroy() end
		for _, event in pairs(self._signals) do event:DisconnectAll() end
		for _, event in pairs(self._propertySignals) do event:DisconnectAll() end
	end
	local Instance = {}
	function Instance.new(className)
		local node = setmetatable({_props = {ClassName = className, Name = className,
			Visible = true, Enabled = true, Scale = 1, Size = UDim2.fromOffset(0, 0),
			Position = if className == "Part" then Vector3.new(0, 0, 0) else UDim2.fromOffset(0, 0),
			AssemblyLinearVelocity = Vector3.new(0, 0, 0), Health = 100, MaxHealth = 100,
			Active = false, CanvasPosition = Vector2.new(0, 0), Text = ""}, _children = {}, _signals = {},
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
		if node.ClassName == "Camera" and (key == "CFrame" or key == "Focus" or key == "CameraType" or key == "CameraSubject") then counters.cameraWrites += 1 end
		if node.ClassName == "UserInputService" and (key == "MouseBehavior" or key == "MouseIconEnabled") then counters.mouseWrites += 1 end
		local old = node._props[key]
		if key == "Parent" then
			detach(node)
			if value then table.insert(value._children, node) end
		end
		node._props[key] = value
		if old ~= value and node._propertySignals[key] then node._propertySignals[key]:Fire() end
		if old ~= value and key == "Parent" then
			if node._signals.AncestryChanged then node._signals.AncestryChanged:Fire(node, value) end
			for _, child in ipairs(node:GetDescendants()) do
				if child._signals.AncestryChanged then child._signals.AncestryChanged:Fire(child, child.Parent) end
			end
		elseif key == "Health" and type(value) == "number" then
			if node._signals.HealthChanged then node._signals.HealthChanged:Fire(value) end
			if value <= 0 and type(old) == "number" and old > 0 and node._signals.Died then node._signals.Died:Fire() end
		end
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
	function world:GetServerTimeNow() return clock end
	local occluded = {}
	function world:Raycast(origin, direction, _params)
		counters.raycasts += 1
		local endpoint = origin + direction
		for target, blocked in pairs(occluded) do
			local part = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
			if blocked and part and (part.Position - endpoint).Magnitude < 0.01 then
				return {Distance = direction.Magnitude / 2, Position = origin + direction / 2, Instance = world}
			end
		end
		return nil
	end
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
	local playerList = {player}
	function players:GetPlayers() counters.candidateScans += 1; return table.clone(playerList) end
	player.UserId = 1
	player.Parent = players
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
	function services.GuiService:GetGuiInset() return Vector2.new(0, 36), Vector2.new(0, 0) end
	local game = {PlaceId = 0}
	function game:GetService(name) assert(services[name], "mock missing service " .. name); return services[name] end
	function game:IsLoaded() return true end
	local frameMeta = {}
	local function frame(position, look)
		return setmetatable({Position = position, LookVector = look or Vector3.new(0, 0, -1)}, frameMeta)
	end
	function frameMeta.__index(value, key)
		if key == "Lerp" then return function(self, other, alpha) return frame(self.Position + (other.Position - self.Position) * alpha, other.LookVector) end end
	end
	function camera:WorldToViewportPoint(position)
		counters.projections += 1
		if self.Projection then return self.Projection(position) end
		local point = Vector3.new(self.ViewportSize.X / 2 + position.X, self.ViewportSize.Y / 2 - position.Y, self.CFrame.Position.Z - position.Z)
		return point, point.X >= 0 and point.X <= self.ViewportSize.X and point.Y >= 0 and point.Y <= self.ViewportSize.Y and point.Z > 0
	end
	camera.CFrame = frame(Vector3.new(0, 2, 20))
	camera.Focus = frame(Vector3.new(0, 2, 0))
	player.CameraMode = Enum.CameraMode.Classic
	local function makeCharacter(target, position)
		local model = Instance.new("Model"); model.Name = target.Name .. "Character"; model.Parent = world
		local root = Instance.new("Part"); root.Name = "HumanoidRootPart"; root.Position = position; root.Parent = model
		local head = Instance.new("Part"); head.Name = "Head"; head.Position = position + Vector3.new(0, 2, 0); head.Parent = model
		local humanoid = Instance.new("Humanoid"); humanoid.Name = "Humanoid"; humanoid.Parent = model
		model.PrimaryPart = root
		target.Character = model
		return model, root, humanoid
	end
	makeCharacter(player, Vector3.new(0, 0, 0))
	camera.CameraSubject = player.Character:FindFirstChildOfClass("Humanoid")
	local env = setmetatable({game = game, workspace = world, Vector2 = Vector2, Vector3 = Vector3,
		UDim = UDim, UDim2 = UDim2, Color3 = Color3, Enum = Enum, Instance = Instance,
		DHPREDICTION_NO_AUTOSTART = true, PINK_DOT_NO_AUTOSTART = true,
		CFrame = {lookAt = function(position, target)
			-- Constructor double only. These tests never emulate camera physics.
			local direction = target - position
			if direction.Magnitude > 0 then direction /= direction.Magnitude end
			return frame(position, direction)
		end, new = function(x, y, z)
			return frame(if type(x) == "table" then x else Vector3.new(x or 0, y or 0, z or 0))
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
			delay = function(delay, callback, ...)
				table.insert(scheduled, {due = clock + delay, callback = callback, arguments = {...}})
			end,
			wait = function() return 0 end},
		warn = print,
		typeof = function(value)
			if type(value) == "table" then
				if value._mockType then return value._mockType end
				if value._props and value._props.ClassName then return "Instance" end
				if type(value.Dot) == "function" and type(value.Z) == "number" then return "Vector3" end
			end
			return typeof(value)
		end,
	}, {__index = getfenv()})
	local result = {env = env, services = services, instances = instances, connections = connections,
		Vector2 = Vector2, playerGui = playerGui, camera = camera, world = world, signal = signal, counters = counters}
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
	function result:advance(seconds)
		clock += seconds
		for index = #scheduled, 1, -1 do
			local pending = scheduled[index]
			if pending.due <= clock then table.remove(scheduled, index); pending.callback(table.unpack(pending.arguments)) end
		end
		services.RunService.RenderStepped:Fire(seconds)
	end
	function result:resetCounters()
		for key in pairs(counters) do counters[key] = 0 end
	end
	function result:addPlayer(name, position)
		local target = Instance.new("Player"); target.Name = name; target.DisplayName = name; target.UserId = #playerList + 1; target.Parent = players
		makeCharacter(target, position or Vector3.new(0, 0, -50))
		table.insert(playerList, target)
		players.PlayerAdded:Fire(target)
		return target
	end
	function result:removePlayer(target)
		players.PlayerRemoving:Fire(target)
		for index, value in ipairs(playerList) do if value == target then table.remove(playerList, index); break end end
		target.Parent = nil
	end
	function result:move(target, position, state)
		local character = target.Character
		character:FindFirstChild("HumanoidRootPart").Position = position
		character:FindFirstChild("Head").Position = position + Vector3.new(0, 2, 0)
		if state then character:FindFirstChildOfClass("Humanoid"):ChangeState(Enum.HumanoidStateType[state]) end
	end
	function result:kill(target) target.Character:FindFirstChildOfClass("Humanoid").Health = 0 end
	function result:respawn(target, position)
		local previous = target.Character
		target.CharacterRemoving:Fire(previous)
		if previous then previous:Destroy() end
		local character = makeCharacter(target, position or Vector3.new(0, 0, -50))
		target.CharacterAdded:Fire(character)
		return character
	end
	function result:setOccluded(target, blocked) occluded[target] = blocked end
	function result:setCameraDistance(distance)
		camera.CFrame = frame(Vector3.new(0, 2, distance))
		camera.Focus = frame(Vector3.new(0, 2, 0))
	end
	function result:input(kind, x, y, key)
		return {UserInputType = Enum.UserInputType[kind], Position = Vector3.new(x or 0, y or 0, 0),
			KeyCode = Enum.KeyCode[key or "Unknown"], UserInputState = Enum.UserInputState.Begin, Changed = signal()}
	end
	return result
end

return Mock
