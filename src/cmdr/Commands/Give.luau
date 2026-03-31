return {
	Name = "give",
	Description = "Gives an inventory item to one or more players.",
	Group = "Developer",
	Args = {
		{
			Type = "inventoryItem",
			Name = "item",
			Description = "The item to give.",
		},
		{
			Type = "players",
			Name = "players",
			Description = "The players who should receive the item.",
		},
		{
			Type = "positiveInteger",
			Name = "amount",
			Description = "How many items to give.",
			Optional = true,
			Default = 1,
		},
	},
}
