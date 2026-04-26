return {
	Name = "damageentity",
	Aliases = { "damageentities", "hurtentity", "hurtentities", "killentity", "killentities" },
	Description = "Damages or kills one nearby matching entity per player.",
	Group = "Developer",
	Args = {
		{
			Type = "entityToken",
			Name = "entity",
			Description = "The entity to target.",
		},
		{
			Type = "players",
			Name = "players",
			Description = "Players used to find nearby matching entities.",
		},
		{
			Type = "positiveInteger",
			Name = "amount",
			Description = "The damage to apply. Leave blank to kill.",
			Optional = true,
		},
	},
}
