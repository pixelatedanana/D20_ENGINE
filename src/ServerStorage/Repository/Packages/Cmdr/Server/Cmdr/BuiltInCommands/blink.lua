-- A fully extensible and type-safe admin-commands console
-- @documentation https://github.com/evaera/Cmdr/blob/master/README.md
-- @source https://github.com/evaera/Cmdr
-- @rostrap Cmdr
-- @author evaera

return {
	Name = "blink";
	Aliases = {"b"};
	Description = "Teleports you to where your mouse is hovering.";
	Group = "DefaultDebug";
	Args = {};

	Run = function(context)
		-- We implement this here because player position is owned by the client.
		-- No reason to bother the server for this!

		local mouse = context.Executor:GetMouse()
		local character = context.Executor.Character

		if not character then
			return "You don't have a character."
		end

		character:MoveTo(mouse.Hit.p)

		return "Blinked!"
	end
}