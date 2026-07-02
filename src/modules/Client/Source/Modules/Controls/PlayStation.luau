local require = require(script.Parent.loader).load(script)

return {
	platform = "Gamepad",
	family = "playstation",
	sections = {
		{
			id = "movement",
			controls = {
				{ id = "move", label = "Move", prompts = { { keyCode = "Thumbstick1", text = "L" } } },
				{ id = "jump", label = "Jump", prompts = { { keyCode = "ButtonX", text = "Cross" } } },
				{ id = "aim_cursor", label = "Aim", prompts = { { keyCode = "Thumbstick2", text = "R" } } },
			},
		},
		{
			id = "actions",
			controls = {
				{
					id = "use_attack_mine_place",
					label = "Use / attack / mine / place",
					prompts = { { keyCode = "ButtonR2", text = "R2" } },
				},
				{
					id = "cycle_hotbar",
					label = "Previous / next hotbar item",
					prompts = { { keyCode = "", text = "L1/R1" } },
				},
			},
		},
		{
			id = "inventory",
			controls = {
				{ id = "interact", label = "Interact", prompts = { { keyCode = "ButtonB", text = "Circle" } } },
				{
					id = "open_inventory",
					actionName = "Inventory.Open",
					label = "Inventory",
					prompts = { { keyCode = "ButtonY", text = "Triangle" } },
				},
				{ id = "drop_trash", label = "Drop / trash", prompts = { { keyCode = "ButtonX", text = "Square" } } },
			},
		},
		{
			id = "system",
			controls = {
				{ id = "pause", label = "Pause", prompts = { { keyCode = "ButtonStart", text = "Options" } } },
			},
		},
	},
} :: any
