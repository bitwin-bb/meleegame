return {
	Name = "damage",
	Aliases = { "hurt" },
	Description = "Damages one or more players.",
	Group = "Developer",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "The players to damage.",
		},
		{
			Type = "positiveInteger",
			Name = "amount",
			Description = "The amount of damage to apply.",
		},
	},
}
