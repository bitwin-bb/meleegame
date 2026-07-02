local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local ARGS = Table.copy({
	{
		Type = "string",
		Name = "subcommand",
		Description = "Use buff or debuff.",
	},
	{
		Type = "string",
		Name = "name",
		Description = "The buff or debuff name.",
	},
})

return {
	Name = "test",
	Description = "Runs developer test commands.",
	Group = "Developer",
	Args = ARGS,
}
