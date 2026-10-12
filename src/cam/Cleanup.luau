--!nonstrict
-- Idempotent ownership of signal connections, render bindings and resources.
local Cleanup={}
Cleanup.__index=Cleanup
function Cleanup.new() return setmetatable({tasks={},destroyed=false},Cleanup) end
function Cleanup:add(callback)
 assert(type(callback)=="function","Cleanup callback required")
 if self.destroyed then pcall(callback) else table.insert(self.tasks,callback) end
 return callback
end
function Cleanup:connect(signal,callback,label)
 local connection=signal:Connect(callback)
 self:add(function() connection:Disconnect() end)
 assert(connection and connection.Connected==true and type(connection.Disconnect)=="function",(label or "Signal").." failed to connect")
 return connection
end
function Cleanup:destroy()
 if self.destroyed then return end
 self.destroyed=true
 for index=#self.tasks,1,-1 do pcall(self.tasks[index]) end
 table.clear(self.tasks)
end
return Cleanup
