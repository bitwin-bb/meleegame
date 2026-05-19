--!strict

return table.freeze({
	image = "rbxassetid://112489474920185",
	frameSize = Vector2.new(110, 166),
	columns = 1,
	rows = 6,
	frameCount = 6,
	pixelsPerStud = 9,
	animations = table.freeze({
		Phase1 = table.freeze({
			frames = table.freeze({ 1, 2, 3 }),
			frameRate = 7,
		}),
		Phase2 = table.freeze({
			frames = table.freeze({ 4, 5, 6 }),
			frameRate = 10,
		}),
	}),
})
