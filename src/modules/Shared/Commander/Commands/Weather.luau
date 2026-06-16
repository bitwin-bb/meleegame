local require = require(script.Parent.loader).load(script)

return {
	Name = "weather",
	Description = "Changes the active weather.",
	Group = "Developer",
	Args = {
		{
			Type = "weatherKind",
			Name = "weather",
			Description = "The weather to apply.",
		},
		{
			Type = "number",
			Name = "transitionSeconds",
			Description = "Optional transition duration in seconds.",
			Optional = true,
		},
	},
}
