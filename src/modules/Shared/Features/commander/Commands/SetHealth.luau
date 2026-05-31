return {
	Name = "sethealth",
	Aliases = { "sethp", "maxhealth" },
	Description = "Permanently sets a player's max health and refills it.",
	Group = "Developer",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "The players to update.",
		},
		{
			Type = "positiveInteger",
			Name = "amount",
			Description = "The new permanent max health value.",
		},
	},
}
