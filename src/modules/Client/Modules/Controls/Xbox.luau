--!strict

return {
	platform = "Gamepad",
	family = "xbox",
	sections = {
		{
			id = "movement",
			controls = {
				{
					id = "move",
					label = "Move",
					prompts = {
						{
							keyCode = "Thumbstick1",
							text = "LS",
						},
					},
				},
				{
					id = "jump",
					label = "Jump",
					prompts = {
						{
							keyCode = "ButtonA",
							text = "A",
						},
					},
				},
				{
					id = "aim_cursor",
					label = "Aim",
					prompts = {
						{
							keyCode = "Thumbstick2",
							text = "RS",
						},
					},
				},
			},
		},
		{
			id = "actions",
			controls = {
				{
					id = "use_attack_mine_place",
					label = "Use / attack / mine / place",
					prompts = {
						{
							keyCode = "ButtonR2",
							text = "RT",
						},
					},
				},
				{
					id = "cycle_hotbar",
					label = "Previous / next hotbar item",
					prompts = {
						{
							text = "LB/RB",
						},
					},
				},
			},
		},
		{
			id = "inventory",
			controls = {
				{
					id = "interact",
					label = "Interact",
					prompts = {
						{
							keyCode = "ButtonB",
							text = "B",
						},
					},
				},
				{
					id = "open_inventory",
					actionName = "Inventory.Open",
					label = "Inventory",
					prompts = {
						{
							keyCode = "ButtonY",
							text = "Y",
						},
					},
				},
				{
					id = "drop_trash",
					label = "Drop / trash",
					prompts = {
						{
							keyCode = "ButtonX",
							text = "X",
						},
					},
				},
			},
		},
		{
			id = "system",
			controls = {
				{
					id = "pause",
					label = "Pause",
					prompts = {
						{
							keyCode = "ButtonStart",
							text = "Menu",
						},
					},
				},
			},
		},
	},
}
