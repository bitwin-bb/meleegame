return {
	Name = "godmode",
	Aliases = { "god", "invincible" },
	Description = "Toggles godmode for one or more players.",
	Group = "Developer",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "The players to affect.",
		},
		{
			Type = "boolean",
			Name = "enabled",
			Description = "Enable or disable godmode. Leave blank to toggle.",
			Optional = true,
		},
	},
}
