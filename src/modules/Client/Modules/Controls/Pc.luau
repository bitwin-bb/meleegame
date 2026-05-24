--!strict

return {
	platform = "KeyboardMouse",
	family = "desktop",
	sections = {
		{
			id = "movement",
			controls = {
				{ id = "move_left", label = "Move left", prompts = { { keyCode = "A", text = "A" } } },
				{ id = "move_right", label = "Move right", prompts = { { keyCode = "D", text = "D" } } },
				{ id = "jump", label = "Jump", prompts = { { keyCode = "Space", text = "Space" } } },
			},
		},
		{
			id = "actions",
			controls = {
				{
					id = "use_attack_mine_place",
					label = "Use / attack / mine / place",
					prompts = { { keyCode = "MouseLeftButton", text = "LMB" } },
				},
				{
					id = "alternate_action",
					label = "Alternate action",
					prompts = { { keyCode = "MouseRightButton", text = "RMB" } },
				},
				{
					id = "cycle_hotbar",
					label = "Previous / next hotbar item",
					prompts = { { keyCode = "", text = "Mouse Wheel" } },
				},
			},
		},
		{
			id = "inventory",
			controls = {
				{ id = "interact", label = "Interact", prompts = { { keyCode = "E", text = "E" } } },
				{
					id = "open_inventory",
					actionName = "Inventory.Open",
					label = "Inventory",
					prompts = { { keyCode = "I", text = "I" } },
				},
				{ id = "drop_trash", label = "Drop / trash", prompts = { { keyCode = "Q", text = "Q" } } },
			},
		},
	},
} :: any
