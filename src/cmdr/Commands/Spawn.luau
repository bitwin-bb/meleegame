return {
	Name = "spawn",
	Description = "Spawns an entity at one or more players.",
	Group = "Developer",
	Args = {
		{
			Type = "entityToken",
			Name = "entity",
			Description = "The entity to spawn.",
		},
		{
			Type = "players",
			Name = "players",
			Description = "The players used as spawn anchors.",
		},
		{
			Type = "positiveInteger",
			Name = "amount",
			Description = "How many entities to spawn per player.",
			Optional = true,
			Default = 1,
		},
	},
}
