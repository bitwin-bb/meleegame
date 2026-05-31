return {
	Name = "time",
	Description = "Sets the world time or toggles the day/night cycle.",
	Group = "Developer",
	Args = {
		{
			Type = "string",
			Name = "action",
			Description = "Use set or cycle.",
		},
		{
			Type = "string",
			Name = "value",
			Description = "A time preset/hour or on/off for the cycle.",
		},
	},
}
