local require = require(script.Parent.loader).load(script)

local Table = require("Table")

local SunAsset = {}

SunAsset.Images = Table.deepReadonly({
	"rbxassetid://130185077109129",
})

function SunAsset.GetImage(): string
	return SunAsset.Images[1]
end

SunAsset.getImage = SunAsset.GetImage

return Table.readonly(SunAsset)
