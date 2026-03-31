local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local function withAliases(
	baseIcons: { [string]: string },
	aliasByKey: { [string]: { string } }
): { [string]: string }
	local output = Sift.Dictionary.copy(baseIcons)
	for key, aliases in aliasByKey do
		local icon = output[key]
		if typeof(icon) ~= "string" or icon == "" then
			continue
		end
		local aliasIcons: { [string]: string } = {}
		for _, alias in aliases do
			aliasIcons[alias] = icon
		end
		output = Sift.Dictionary.merge(output, aliasIcons)
	end
	return output
end

local copperAxeIcon = "rbxassetid://75765746802617"
local copperPickaxeIcon = "rbxassetid://135500881364781"
local copperOreIcon = "rbxassetid://86523519459129"
local gelIcon = "rbxassetid://125223837467164"

local weaponIcons = {
	sword = "rbxassetid://120461830147890",
	pickaxe = copperPickaxeIcon,
	axe = copperAxeIcon,
	hammer = "rbxassetid://122769702567537",
}
local questionMarkIcon = "rbxassetid://105837137977667"
local lifeFruitHeartIcon = "rbxassetid://111119749912611"

local itemIcons = withAliases({
	default = questionMarkIcon,
	sword = weaponIcons.sword,
	copperShortSword = weaponIcons.sword,
	pickaxe = weaponIcons.pickaxe,
	axe = weaponIcons.axe,
	hammer = weaponIcons.hammer,
	coin = "rbxassetid://138124828857039",
	consumable = "rbxassetid://111119749912611",
	copperBroadSword = "rbxassetid://113224739547545",
	katana = "rbxassetid://126443058539668",
	wood = "rbxassetid://90861819791983",
	vine = "rbxassetid://113394798642381",
	stone = "rbxassetid://101907341766242",
	richMahogany = "rbxassetid://102173755012342",
	jungleWood = "rbxassetid://102173755012342",
	mud = "rbxassetid://140267522619940",
	ebonWood = "rbxassetid://94067001703630",
	ebonStone = "rbxassetid://84325236351785",
	dirt = "rbxassetid://79897470188136",
	acorn = "rbxassetid://89910393519002",
	workbench = "rbxassetid://127346854237238",
	gel = gelIcon,
	gelIcon = gelIcon,
	copperOre = copperOreIcon,
	copperOreIcon = copperOreIcon,
	copperAxeIcon = copperAxeIcon,
	copperPickaxeIcon = copperPickaxeIcon,
}, {
	default = { "weapon", "shortsword", "broadsword" },
	copperShortSword = { "coppershortsword" },
	copperBroadSword = { "copperbroadsword" },
	copperOre = { "copperore" },
	gel = { "Gel", "gelIcon" },
	richMahogany = { "richmahogany" },
	jungleWood = { "junglewood" },
})

return {
	normalHeart = "rbxassetid://105126599485879",
	heartLifeFruit = lifeFruitHeartIcon,
	lifeFruitHeart = lifeFruitHeartIcon,
	inventorySlot = "rbxassetid://101539278639866",
	inventorySlotHovered = "rbxassetid://84425714531334",
	expandInventory = "rbxassetid://105988157243321",
	expandInventoryPressed = "rbxassetid://88978873911129",
	flame = "rbxassetid://95323881188879",
	bubble = "rbxassetid://95054079842580",
	mana = "rbxassetid://106874227216963",
	skillSlot = "rbxassetid://85792602964984",
	mouseHover = "rbxassetid://83519351122072",
	mouseClick = "rbxassetid://135598322490251",
	mouse = "rbxassetid://71314829332403",
	trashCanClosed = "rbxassetid://120876985096485",
	trashCanOpen = "rbxassetid://133660338974960",
	glareUnderline = "rbxassetid://92219399507426",
	miningProgressBar = "rbxassetid://97232371963727",
	miningProgressFrame = "rbxassetid://105210418949426",
	craftingIconPress = "rbxassetid://71167003932351",
	craftItemSlot = "rbxassetid://131825319311584",
	craftButton = "rbxassetid://114851769110143",
	craftButtonPressed = "rbxassetid://71167003932351",
	finalCraftButton = "rbxassetid://90417499799963",
	finalCraftButtonPressed = "rbxassetid://103228470751134",
	craftingMenu = "rbxassetid://79546150230515",
	craftingMenuCategory = "rbxassetid://133434385354667",
	craftingMenuCategoryPressed = "rbxassetid://125140152167084",
	craftingMenuInner = "rbxassetid://73368761402049",
	craftingMenuTextBox = "rbxassetid://98196498320236",
	recipeIcon = "rbxassetid://114344383327166",
	marker = "rbxassetid://72558733619067",
	eocIcon = "rbxassetid://119845369401414",
	questionMark = questionMarkIcon,
	spriteSheets = {
		copperCoin = "rbxassetid://138124828857039",
		silverCoin = "rbxassetid://81978209477040",
		goldCoin = "rbxassetid://126752862632183",
		platinumCoin = "rbxassetid://88193310457943",
	},
	weaponIcons = weaponIcons,
	itemIcons = itemIcons,
}
