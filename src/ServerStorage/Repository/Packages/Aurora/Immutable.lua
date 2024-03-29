-- Aurora is a library that can manage status effects (known as "Auras") in your Roblox game.
-- @documentation https://github.com/evaera/Aurora/blob/master/README.md
-- @source https://github.com/evaera/Aurora/tree/master/lib
-- @rostrap Aurora
-- @author evaera

-- Maybe this will be its own library some day

local Immutable = {}

function Immutable.Lock(Table)
	return setmetatable({}, {
		__index = function(_, k)
			if k == "__keys" then
				local keys = {}
				for key in pairs(Table) do
					keys[key] = true
				end
				return keys
			end

			return Table[k]
		end;

		__newindex = function()
			error("Attempt to change immutable object", 2)
		end;

		__metatable = "Attempt to get metatable of immutable object";
	})
end

return Immutable