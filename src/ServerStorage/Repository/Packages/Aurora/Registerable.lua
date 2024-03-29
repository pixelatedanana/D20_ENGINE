-- Aurora is a library that can manage status effects (known as "Auras") in your Roblox game.
-- @documentation https://github.com/evaera/Aurora/blob/master/README.md
-- @source https://github.com/evaera/Aurora/tree/master/lib
-- @rostrap Aurora
-- @author evaera


local RunService = game:GetService("RunService")
local Immutable = require(script.Parent.Immutable)

local IsServer = RunService:IsServer()

local Registerable = {}
Registerable.__index = Registerable

local Caches = setmetatable({}, { __mode = "k" })

function Registerable.new(name)
	local self = {
		Name = name;
		Roots = {};
	}
	setmetatable(self, Registerable)

	Caches[self] = {}

	return self
end

function Registerable:LookIn(object)
	self.Roots[#self.Roots + 1] = object
end

function Registerable:Find(name, skipServerCheck)
	if Caches[self][name] then
		return Caches[self][name]
	end

	local serverEquiv
	if IsServer and not skipServerCheck then
		serverEquiv = self:Find(name .. "Server", true)
	end

	for _, root in ipairs(self.Roots) do
		local module = root:FindFirstChild(name, true)
		if module and module:IsA("ModuleScript") then
			local export = require(module)

			if serverEquiv then
				for key in pairs(serverEquiv.__keys) do
					export[key] = serverEquiv[key]
				end
			end

			Caches[self][name] = Immutable.Lock(export)
			return Caches[self][name]
		end
	end
end

return Registerable