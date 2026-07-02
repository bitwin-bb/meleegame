local require = require(script.Parent.loader).load(script)

return table.freeze({
	image = "rbxassetid://114931330293490",
	frameSize = Vector2.new(64, 32),
	columns = 1,
	rows = 2,
	frameCount = 2,
	pixelsPerStud = 30,
	contentBounds = table.freeze({
		min = Vector2.new(2, 7),
		max = Vector2.new(62, 31),
	}),
	animations = table.freeze({
		Idle = table.freeze({
			frames = table.freeze({ 1, 2 }),
			frameRate = 4,
			minFrameRate = 3,
			maxFrameRate = 13,
		}),
		Hop = table.freeze({
			frames = table.freeze({ 2 }),
			frameRate = 1,
		}),
		Dead = table.freeze({
			frames = table.freeze({ 2 }),
			frameRate = 1,
		}),
		Gore = table.freeze({
			frames = table.freeze({ 1, 2 }),
			frameRate = 12,
		}),
	}),
})
