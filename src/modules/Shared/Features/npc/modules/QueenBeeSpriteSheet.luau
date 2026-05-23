--!strict

return table.freeze({
	image = "rbxassetid://94995744392021",
	frameSize = Vector2.new(172, 152),
	columns = 1,
	rows = 12,
	frameCount = 12,
	pixelsPerStud = 12,
	animations = table.freeze({
		Charge = table.freeze({
			frames = table.freeze({ 1, 2, 3, 4 }),
			frameRate = 14,
		}),
		Idle = table.freeze({
			frames = table.freeze({ 5, 6, 7, 8, 9, 10, 11, 12 }),
			frameRate = 11,
		}),
	}),
})
