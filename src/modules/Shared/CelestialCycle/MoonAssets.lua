local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local MoonAssets = {}

MoonAssets.ImagesByPhase = Table.deepReadonly({
	fullMoon = "rbxassetid://71652201703042",
	new = "rbxassetid://73088477000613",
	waxingGibbous = "rbxassetid://110054209286689",
	waningGibbous = "rbxassetid://133426730044312",
	waningCrescent = "rbxassetid://71828721926188",
	thirdQuarter = "rbxassetid://85935416509317",
	firstQuarter = "rbxassetid://77620348569206",
	waxingCrescent = "rbxassetid://137582270298372",
})

function MoonAssets.GetImageForPhase(phaseNameRaw: any): string
	local phaseName = if typeof(phaseNameRaw) == "string" then phaseNameRaw else "new"
	return MoonAssets.ImagesByPhase[phaseName] or MoonAssets.ImagesByPhase.new
end

MoonAssets.getImageForPhase = MoonAssets.GetImageForPhase

return Table.readonly(MoonAssets)
