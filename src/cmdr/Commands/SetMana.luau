return {
	Name = "setmana",
	Aliases = { "maxmana" },
	Description = "Permanently sets a player's max mana and refills it.",
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
			Description = "The new permanent max mana value.",
		},
	},
}
