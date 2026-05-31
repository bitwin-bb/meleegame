return {
	Name = "heal",
	Description = "Heals one or more players.",
	Group = "Developer",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "The players to heal.",
		},
		{
			Type = "positiveInteger",
			Name = "amount",
			Description = "The amount to heal. Leave blank to fully heal.",
			Optional = true,
		},
	},
}
