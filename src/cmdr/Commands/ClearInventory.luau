return {
	Name = "clearinventory",
	Aliases = { "clearinv" },
	Description = "Clears one or more players' inventories.",
	Group = "Developer",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "The players whose inventories should be cleared.",
		},
	},
}
