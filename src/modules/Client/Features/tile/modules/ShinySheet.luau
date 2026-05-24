--!strict

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = (require :: any)(loaderUtils.Parent).load(packageRoot)

local Table = loader("Table")

return table.freeze(Table.copy({
	image = "rbxassetid://112548159625239",
	columns = 5,
	rows = 1,
	frameSize = Vector2.new(15, 15),
	frameRate = 18,
}))
