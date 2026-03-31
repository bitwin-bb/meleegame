local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CmdrUtils = require(ReplicatedStorage.Shared.Cmdr.CmdrUtils)

return {
	Name = "fly",
	Description = "Enables developer fly movement for one or more players.",
	Group = "Developer",
	Args = {
		{
			Type = "players",
			Name = "players",
			Description = "The players to make fly.",
		},
		{
			Type = "positiveInteger",
			Name = "speed",
			Description = "Fly speed in studs per second.",
			Optional = true,
			Default = CmdrUtils.DEFAULT_FLY_SPEED,
		},
	},
}
