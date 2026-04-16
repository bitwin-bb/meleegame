local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sift = require(ReplicatedStorage.Packages.Sift)

local function withAliases(baseIcons: { [string]: string }, aliasByKey: { [string]: { string } }): { [string]: string }
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

local hints = {
	keyboard = {
		[Enum.KeyCode.A] = "rbxassetid://106567914960693",
		[Enum.KeyCode.B] = "rbxassetid://93942557117561",
		[Enum.KeyCode.C] = "rbxassetid://73938035270751",
		[Enum.KeyCode.D] = "rbxassetid://132790717119288",
		[Enum.KeyCode.E] = "rbxassetid://136590271816477",
		[Enum.KeyCode.F] = "rbxassetid://102396597493191",
		[Enum.KeyCode.G] = "rbxassetid://111433199008675",
		[Enum.KeyCode.H] = "rbxassetid://127285084289020",
		[Enum.KeyCode.I] = "rbxassetid://119996050986381",
		[Enum.KeyCode.J] = "rbxassetid://105653294482350",
		[Enum.KeyCode.K] = "rbxassetid://75504871985204",
		[Enum.KeyCode.L] = "rbxassetid://133916917072027",
		[Enum.KeyCode.M] = "rbxassetid://95054444625827",
		[Enum.KeyCode.N] = "rbxassetid://94847088821931",
		[Enum.KeyCode.O] = "rbxassetid://94153119110032",
		[Enum.KeyCode.P] = "rbxassetid://84857838830427",
		[Enum.KeyCode.Q] = "rbxassetid://85368622180947",
		[Enum.KeyCode.R] = "rbxassetid://107331508406054",
		[Enum.KeyCode.S] = "rbxassetid://129469799241178",
		[Enum.KeyCode.T] = "rbxassetid://109217481144680",
		[Enum.KeyCode.U] = "rbxassetid://127594433018578",
		[Enum.KeyCode.V] = "rbxassetid://83541439256096",
		[Enum.KeyCode.W] = "rbxassetid://81597945257386",
		[Enum.KeyCode.X] = "rbxassetid://106860420712624",
		[Enum.KeyCode.Y] = "rbxassetid://84888804386263",
		[Enum.KeyCode.Z] = "rbxassetid://85981922194782",
		[Enum.KeyCode.Zero] = "rbxassetid://103060919530543",
		[Enum.KeyCode.One] = "rbxassetid://99320815768571",
		[Enum.KeyCode.Two] = "rbxassetid://90713115313249",
		[Enum.KeyCode.Three] = "rbxassetid://136236373663858",
		[Enum.KeyCode.Four] = "rbxassetid://88288258406940",
		[Enum.KeyCode.Five] = "rbxassetid://85826144381423",
		[Enum.KeyCode.Six] = "rbxassetid://102175868358774",
		[Enum.KeyCode.Seven] = "rbxassetid://120107879851574",
		[Enum.KeyCode.Eight] = "rbxassetid://132515780873117",
		[Enum.KeyCode.Nine] = "rbxassetid://77885589335149",
		[Enum.KeyCode.Space] = "rbxassetid://116330275913663",
		[Enum.KeyCode.Return] = "rbxassetid://126563602616414",
		[Enum.KeyCode.Tab] = "rbxassetid://96989294242245",
		[Enum.KeyCode.Backspace] = "rbxassetid://104293586781939",
		[Enum.KeyCode.Escape] = "rbxassetid://104450053249683",
		[Enum.KeyCode.Up] = "rbxassetid://87238900992629",
		[Enum.KeyCode.Down] = "rbxassetid://133104334052392",
		[Enum.KeyCode.Left] = "rbxassetid://109748011270973",
		[Enum.KeyCode.Right] = "rbxassetid://135823944185304",
		[Enum.KeyCode.LeftShift] = "rbxassetid://90560288961887",
		[Enum.KeyCode.RightShift] = "rbxassetid://90560288961887",
		[Enum.KeyCode.LeftControl] = "rbxassetid://101475762269004",
		[Enum.KeyCode.RightControl] = "rbxassetid://101475762269004",
		[Enum.KeyCode.LeftAlt] = "rbxassetid://115928341989586",
		[Enum.KeyCode.RightAlt] = "rbxassetid://115928341989586",
		[Enum.KeyCode.Slash] = "rbxassetid://139246336579713",
		[Enum.KeyCode.Semicolon] = "rbxassetid://89284856298608",
		[Enum.KeyCode.Quote] = "rbxassetid://115432403988621",
		[Enum.KeyCode.Minus] = "rbxassetid://123122590911338",
		[Enum.KeyCode.LeftBracket] = "rbxassetid://111481567393699",
		[Enum.KeyCode.RightBracket] = "rbxassetid://97207123946239",
		[Enum.KeyCode.BackSlash] = "rbxassetid://139246336579713",
		[Enum.KeyCode.MouseLeftButton] = "rbxassetid://124503412360112",
		[Enum.KeyCode.MouseRightButton] = "rbxassetid://115799487501082",
		[Enum.KeyCode.MouseMiddleButton] = "rbxassetid://97120801583108",
	},
	xbox = {
		[Enum.KeyCode.ButtonA] = "rbxassetid://121056661169708",
		[Enum.KeyCode.ButtonB] = "rbxassetid://74382587467013",
		[Enum.KeyCode.ButtonX] = "rbxassetid://100175429624309",
		[Enum.KeyCode.ButtonY] = "rbxassetid://86096454362572",
		[Enum.KeyCode.ButtonL1] = "rbxassetid://126218287657288",
		[Enum.KeyCode.ButtonR1] = "rbxassetid://95649500244183",
		[Enum.KeyCode.ButtonL2] = "rbxassetid://92789360182519",
		[Enum.KeyCode.ButtonR2] = "rbxassetid://98002716864197",
		[Enum.KeyCode.ButtonL3] = "rbxassetid://110802589523435",
		[Enum.KeyCode.ButtonR3] = "rbxassetid://114005394722262",
		[Enum.KeyCode.ButtonStart] = "rbxassetid://106385958705978",
		[Enum.KeyCode.ButtonSelect] = "rbxassetid://98742497173720",
		[Enum.KeyCode.DPadUp] = "rbxassetid://91339653952836",
		[Enum.KeyCode.DPadDown] = "rbxassetid://104669231341837",
		[Enum.KeyCode.DPadLeft] = "rbxassetid://70817433334175",
		[Enum.KeyCode.DPadRight] = "rbxassetid://100359799830093",
	},
	playstation = {
		[Enum.KeyCode.ButtonA] = "rbxassetid://83055964101519",
		[Enum.KeyCode.ButtonB] = "rbxassetid://103436293787842",
		[Enum.KeyCode.ButtonX] = "rbxassetid://119213726450334",
		[Enum.KeyCode.ButtonY] = "rbxassetid://105613821877337",
		[Enum.KeyCode.ButtonL1] = "rbxassetid://76595701899478",
		[Enum.KeyCode.ButtonR1] = "rbxassetid://103433116690568",
		[Enum.KeyCode.ButtonL2] = "rbxassetid://103003728115809",
		[Enum.KeyCode.ButtonR2] = "rbxassetid://98485031834725",
		[Enum.KeyCode.ButtonL3] = "rbxassetid://121661463374661",
		[Enum.KeyCode.ButtonR3] = "rbxassetid://82115243873064",
		[Enum.KeyCode.ButtonStart] = "rbxassetid://74783320689085",
		[Enum.KeyCode.ButtonSelect] = "rbxassetid://116587088401417",
		[Enum.KeyCode.DPadUp] = "rbxassetid://109098609680858",
		[Enum.KeyCode.DPadDown] = "rbxassetid://87887123801845",
		[Enum.KeyCode.DPadLeft] = "rbxassetid://79929158253781",
		[Enum.KeyCode.DPadRight] = "rbxassetid://70780762403440",
	},
	mobile = {
		[Enum.KeyCode.Touch] = "rbxassetid://104057783653073",
	},
}

local platform = {
	gamepadNav = "rbxassetid://139208197032599",
}

local copperAxeIcon = "rbxassetid://75765746802617"
local copperPickaxeIcon = "rbxassetid://135500881364781"
local copperOreIcon = "rbxassetid://86523519459129"
local gelIcon = "rbxassetid://125223837467164"
local torchItemIcon = "rbxassetid://117501832045596"

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
	torch = torchItemIcon,
	torchIcon = torchItemIcon,
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
	torch = { "Torch", "torchIcon" },
	richMahogany = { "richmahogany" },
	jungleWood = { "junglewood" },
})

return {
	hints = hints,
	platform = platform,
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
