local require = require(script.Parent.loader).load(script)

return {
	platform = "Touch",
	family = "mobile",
	sections = {
		{
			id = "movement",
			controls = {
				{ id = "move", label = "Move", prompts = { { keyCode = "Touch", text = "Stick" } } },
				{ id = "jump", label = "Jump", prompts = { { keyCode = "Touch", text = "Jump" } } },
				{ id = "aim_cursor", label = "Aim", prompts = { { keyCode = "Touch", text = "Drag" } } },
			},
		},
		{
			id = "actions",
			controls = {
				{
					id = "use_attack_mine_place",
					label = "Use / attack / mine / place",
					prompts = { { keyCode = "Touch", text = "Tap" } },
				},
				{
					id = "cycle_hotbar",
					label = "Previous / next hotbar item",
					prompts = { { keyCode = "Touch", text = "Hotbar" } },
				},
			},
		},
		{
			id = "inventory",
			controls = {
				{
					id = "open_inventory",
					actionName = "Inventory.Open",
					label = "Inventory",
					prompts = { { keyCode = "Touch", text = "Bag" } },
				},
				{
					id = "drop_trash",
					actionName = "",
					label = "Drop / trash",
					prompts = { { keyCode = "Touch", text = "Drag" } },
				},
			},
		},
	},
} :: any
