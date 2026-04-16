local DEFAULT_FLY_SPEED = 64

return {
	Name = "fly",
	Description = "Enables developer fly movement for one or more players.",
	Group = "Developer",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "The players to make fly.",
		},
		{
			Type = "positiveInteger",
			Name = "speed",
			Description = "Fly speed in studs per second.",
			Optional = true,
			Default = DEFAULT_FLY_SPEED,
		},
	},
}
