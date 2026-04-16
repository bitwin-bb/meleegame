return {
	Name = "matterdebug",
	Aliases = { "debugmenu", "mattermenu" },
	Description = "Shows or hides the Matter debug menu for one or more players.",
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
			Description = "Enable or disable the Matter debug menu. Leave blank to toggle.",
			Optional = true,
		},
	},
}
