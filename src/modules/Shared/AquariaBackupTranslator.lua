--!strict
--[[
	@class AquariaBackupTranslator
]]

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local require = require(loaderUtils.Parent).load(script)

return require("JSONTranslator").new("AquariaBackupTranslator", "en", {
	gameName = "AquariaBackup",
	notifications = {
		build = {
			place = {
				generic = "Can't place that there.",
				invalid_tile_coordinate_or_id = "That placement target is invalid.",
				selected_item_not_placeable = "That item can't be placed.",
				selected_item_tile_mismatch = "That item does not match this tile.",
				tile_out_of_bounds = "You can't build there.",
				out_of_range = "You're too far away to build there.",
				occupied = "That space is already occupied.",
				missing_support = "That tile needs support first.",
				cannot_place_air = "Air can't be placed.",
				empty_footprint = "That item has nothing to place.",
			},
			["break"] = {
				generic = "Can't break that right now.",
				invalid_tile_coordinate = "That break target is invalid.",
				tile_out_of_bounds = "You can't break that there.",
				out_of_range = "You're too far away to break that.",
				input_timeout = "Breaking timed out.",
				invalid_target = "There's nothing valid to break there.",
				air = "There's nothing there.",
				tree_already_felled = "That tree is already down.",
				tile_requires_pickaxe = "You need a pickaxe for that.",
				insufficient_pickaxe_power = "Your pickaxe isn't strong enough.",
				invalid_tile_id = "That tile can't be broken.",
			},
		},
		crafting = {
			success = "Crafted {quantity}x {itemName}",
			failure = {
				generic = "Crafting failed.",
				not_ready = "Crafting isn't ready yet.",
				rate_limited = "You're crafting too quickly.",
				invalid_request = "That craft request is invalid.",
				invalid_recipe = "That recipe doesn't exist.",
				recipe_locked = "You haven't unlocked that recipe yet.",
				busy = "Crafting is busy right now.",
				missing_station = "You need the right crafting station.",
				wrong_biome = "You need to be in the right biome.",
				transaction_error = "Crafting hit an internal error.",
				missing_items = "You don't have the required materials.",
				inventory_full = "Your inventory is full.",
			},
		},
	},
})
