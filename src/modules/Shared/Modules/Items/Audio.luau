--!strict
local Pickaxes = require(script.Parent.Pickaxes)

return {
	Music = {
		OverworldDay = "rbxassetid://122358683605709",
		OverworldNight = "rbxassetid://132162981071821",
		Corruption = "rbxassetid://89421894972000",
		Jungle = "rbxassetid://88997911200453",
		BrainOfCthulhu = "rbxassetid://73310205953319",
		WallOfFlesh = "rbxassetid://76944291678064",
		OverworldDayCalamity = "rbxassetid://74013306149777",
		Title = "rbxassetid://16383633205",
		EyeOfCthulhu = "rbxassetid://118342611588852",
		Cavern = "rbxassetid://135190767488877",
		Underground = "rbxassetid://122174376611444",
		Desert = "rbxassetid://110380615662801",
		Snow = "rbxassetid://82496140751964",
		Rain = "rbxassetid://110148836882951",
		UndergroundCorruption = "rbxassetid://133175187074428",
		EyeOfCthulhuRedux = "rbxassetid://73783286159203",
	},
	Npcs = {
		Slimes = {
			Default = {
				Hurt = {
					"rbxassetid://128251385051448",
					"rbxassetid://82369877422855",
					"rbxassetid://88152194616240",
				},
				Death = {
					"rbxassetid://95350652986257",
					"rbxassetid://131057043336047",
					"rbxassetid://129751945121242",
				},
				Jump = {
					"rbxassetid://87722006933286",
					"rbxassetid://128495657900967",
					"rbxassetid://103426790889570",
				},
				Land = {
					"rbxassetid://120212590065651",
					"rbxassetid://92516935838935",
					"rbxassetid://101135542203579",
				},
			},
			GreenSlime = {
				Hurt = {
					"rbxassetid://128251385051448",
					"rbxassetid://82369877422855",
					"rbxassetid://88152194616240",
				},
				Death = {
					"rbxassetid://95350652986257",
					"rbxassetid://131057043336047",
					"rbxassetid://129751945121242",
				},
				Jump = {
					"rbxassetid://87722006933286",
					"rbxassetid://128495657900967",
					"rbxassetid://103426790889570",
				},
				Land = {
					"rbxassetid://120212590065651",
					"rbxassetid://92516935838935",
					"rbxassetid://101135542203579",
				},
			},
		},
	},
	Player = {
		Walk = {
			Default = {
				"rbxassetid://139218459028027",
				"rbxassetid://135661992057340",
				"rbxassetid://118171247776690",
				"rbxassetid://99678905942335",
			},
			Plastic = {
				"rbxassetid://139218459028027",
				"rbxassetid://135661992057340",
				"rbxassetid://118171247776690",
				"rbxassetid://99678905942335",
			},
			Dirt = {
				"rbxassetid://70613938354919",
				"rbxassetid://73189723454250",
				"rbxassetid://85098154840446",
				"rbxassetid://78685079799800",
			},
			Stone = {
				"rbxassetid://70613938354919",
				"rbxassetid://73189723454250",
				"rbxassetid://85098154840446",
				"rbxassetid://78685079799800",
			},
			Grass = {
				"rbxassetid://110916840535817",
				"rbxassetid://104414031461916",
				"rbxassetid://98036398008424",
				"rbxassetid://95096400753854",
			},
			Wood = {
				"rbxassetid://73970805826355",
				"rbxassetid://78724561577501",
				"rbxassetid://77792575599157",
				"rbxassetid://74978166551807",
			},
			Metal = {
				"rbxassetid://134158390225401",
				"rbxassetid://99264815020652",
				"rbxassetid://73835982692201",
				"rbxassetid://137551819745308",
			},
			Snow = {
				"rbxassetid://96739494925672",
				"rbxassetid://105900849260487",
				"rbxassetid://106747482840476",
				"rbxassetid://101980065058830",
			},
			Sand = {
				"rbxassetid://8453417974",
				"rbxassetid://109565823661998",
				"rbxassetid://18642869167",
				"rbxassetid://18642867368",
			},
			Ground = {
				"rbxassetid://70613938354919",
				"rbxassetid://73189723454250",
				"rbxassetid://85098154840446",
				"rbxassetid://78685079799800",
			},
			WoodPlanks = {
				"rbxassetid://93362771418104",
				"rbxassetid://91500330512189",
				"rbxassetid://88241122706351",
				"rbxassetid://86403700569364",
			},
			DiamondPlate = {
				"rbxassetid://134158390225401",
				"rbxassetid://99264815020652",
				"rbxassetid://73835982692201",
				"rbxassetid://137551819745308",
			},
			Concrete = {
				"rbxassetid://128083760642409",
				"rbxassetid://86082095505293",
				"rbxassetid://84272541885035",
				"rbxassetid://106886087227576",
			},
			Brick = {},
			Slate = {},
			Cobblestone = {},
		},
		Hurt = {
			"rbxassetid://135119591308242",
			"rbxassetid://120369547849136",
		},
		Land = {
			Default = {
				"rbxassetid://139218459028027",
				"rbxassetid://135661992057340",
				"rbxassetid://118171247776690",
				"rbxassetid://99678905942335",
			},
			Grass = {
				"rbxassetid://110916840535817",
				"rbxassetid://104414031461916",
				"rbxassetid://98036398008424",
				"rbxassetid://95096400753854",
			},
			Ground = {
				"rbxassetid://70613938354919",
				"rbxassetid://73189723454250",
				"rbxassetid://85098154840446",
				"rbxassetid://78685079799800",
			},
			Sand = {
				"rbxassetid://8453417974",
				"rbxassetid://109565823661998",
				"rbxassetid://18642869167",
				"rbxassetid://18642867368",
			},
			Snow = {
				"rbxassetid://96739494925672",
				"rbxassetid://105900849260487",
				"rbxassetid://106747482840476",
				"rbxassetid://101980065058830",
			},
		},
		Jump = {
			"rbxassetid://78685079799800",
			"rbxassetid://85098154840446",
		},
		Pickup = {
			Coin = {},
			Item = {
				"rbxassetid://133331985238497",
				"rbxassetid://112761559587899",
				"rbxassetid://110028051548943",
				"rbxassetid://101350901770617",
				"rbxassetid://79480035097773",
			},
		},
	},
	Loot = {
		CoinDrop = {},
		CoinPickup = {},
		ItemPickup = {
			"rbxassetid://133331985238497",
			"rbxassetid://112761559587899",
			"rbxassetid://110028051548943",
			"rbxassetid://101350901770617",
			"rbxassetid://79480035097773",
		},
	},
	Items = {
		Weapons = {
			CopperBroadSword = {
				Equip = "rbxassetid://93174431767689",
				Swings = {
					"rbxassetid://100378536881718",
					"rbxassetid://86344294973582",
					"rbxassetid://79732830869206",
				},
			},
			CopperShortSword = {},
			Katana = {},
		},
		Axes = {
			CopperAxe = {
				Equip = "rbxassetid://93174431767689",
				Swings = {
					"rbxassetid://89016100493144",
					"rbxassetid://86985320830309",
					"rbxassetid://132249368313234",
					"rbxassetid://90536300513403",
				},
			},
		},
		Pickaxes = {
			CopperPickaxe = {
				Equip = "rbxassetid://93174431767689",
				Swings = {
					"rbxassetid://100378536881718",
					"rbxassetid://86344294973582",
					"rbxassetid://79732830869206",
				},
			},
		},
	},
	UI = {
		Hover = "rbxassetid://113222164891779",
		Press = "rbxassetid://74248924662708",
		Click = "rbxassetid://91512234022449",
		TrashCanOpen = "rbxassetid://9116438441",
		TrashCanClose = "rbxassetid://9116439227",
		Trash = "rbxassetid://9125723704",
		ItemPickup = "rbxassetid://74248924662708",
		ItemPutDown = "rbxassetid://122174168341421",
		Craft = "rbxassetid://98310051876142",
		Drag = "rbxassetid://74396890203317",
	},
	Misc = {
		Tree = {
			Impact = {},
			Chop = {
				"rbxassetid://9120808133",
				"rbxassetid://9120807657",
				"rbxassetid://9120808413",
				"rbxassetid://9120807871",
			},
			Fall = {},
		},
		Water = {
			"rbxassetid://87702599635040",
			"rbxassetid://83673781452193",
			"rbxassetid://6569949256",
			"rbxassetid://5930519356",
		},
		Tile = {
			Hit = {
				"rbxassetid://9103759121",
				"rbxassetid://9103759039",
				"rbxassetid://9120146349",
			},
			Break = {
				"rbxassetid://8666682639",
				"rbxassetid://8666681117",
				"rbxassetid://8666679694",
				"rbxassetid://8666678078",
				"rbxassetid://8666678762",
			},
		},
		Weather = {
			Rain = "rbxassetid://81671946901796",
			Thunder = {
				"rbxassetid://140089926923698",
				"rbxassetid://139319051979882",
				"rbxassetid://118514478805322",
			},
		}
	},
}
