--!strict

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local nevermoreRequire = require(loaderUtils.Parent).load(script)

local ScreenGuiService = nevermoreRequire("ScreenGuiService")
local SnackbarServiceClient = nevermoreRequire("SnackbarServiceClient")
local NevermoreSupport = require(script:FindFirstAncestor("game").Shared.Modules.Core.NevermoreSupport)
local AquariaBackupTranslator = require(script:FindFirstAncestor("game").Shared.AquariaBackupTranslator)

local NevermoreNotificationServiceClient = {}

local screenGuiCleanup = nil :: (() -> ())?
local lastShownAtByKey = {} :: { [string]: number }

local DEFAULT_DEDUPE_WINDOW_SECONDS = 0.6

local function getTranslator()
	return NevermoreSupport.getService(AquariaBackupTranslator)
end

local function getScreenGuiService()
	return NevermoreSupport.getService(ScreenGuiService)
end

local function getSnackbarService()
	return NevermoreSupport.getService(SnackbarServiceClient)
end

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end

	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function humanizeReason(reasonRaw: any): string
	local reason = trim(reasonRaw)
	if reason == "" then
		return "Something went wrong."
	end

	reason = string.gsub(reason, "_", " ")
	return string.upper(string.sub(reason, 1, 1)) .. string.sub(reason, 2)
end

local function translate(translationKey: string, args: { [string]: any }?): string?
	if translationKey == "" then
		return nil
	end

	local ok, text = pcall(function()
		return getTranslator():FormatByKey(translationKey, args)
	end)

	if ok and typeof(text) == "string" and text ~= "" then
		return text
	end

	return nil
end

local function shouldSuppress(dedupeKey: string, windowRaw: any): boolean
	local window = DEFAULT_DEDUPE_WINDOW_SECONDS
	if typeof(windowRaw) == "number" and windowRaw == windowRaw then
		window = math.max(0, windowRaw)
	end

	local now = os.clock()
	local lastShownAt = lastShownAtByKey[dedupeKey]
	if lastShownAt ~= nil and (now - lastShownAt) < window then
		return true
	end

	lastShownAtByKey[dedupeKey] = now
	return false
end

local function resolveRecipeDisplayName(craftingServiceRaw: any, recipeIdRaw: any): string
	local recipeId = trim(recipeIdRaw)
	if recipeId == "" then
		return "item"
	end

	if typeof(craftingServiceRaw) == "table" then
		local registry = (craftingServiceRaw :: any).registry
		if typeof(registry) == "table" and typeof((registry :: any).recipesById) == "table" then
			local recipe = (registry :: any).recipesById[recipeId]
			if typeof(recipe) == "table" and typeof((recipe :: any).displayName) == "string" then
				return (recipe :: any).displayName
			end
		end
	end

	return humanizeReason(recipeId)
end

function NevermoreNotificationServiceClient.SetScreenGui(screenGui: ScreenGui)
	if screenGuiCleanup ~= nil then
		screenGuiCleanup()
		screenGuiCleanup = nil
	end

	getSnackbarService():ClearQueue(true)
	screenGuiCleanup = getScreenGuiService():SetGuiParent(screenGui)
end

function NevermoreNotificationServiceClient.ShowText(textRaw: any, optionsRaw: any?)
	local text = trim(textRaw)
	if text == "" then
		return nil
	end

	local options = if typeof(optionsRaw) == "table" then (optionsRaw :: { [string]: any }) else {}
	local dedupeKey = if typeof(options.dedupeKey) == "string" and options.dedupeKey ~= "" then options.dedupeKey else text
	if shouldSuppress(dedupeKey, options.dedupeWindowSeconds) then
		return nil
	end

	if options.clearQueue == true then
		getSnackbarService():ClearQueue(options.doNotAnimate == true)
	elseif options.hideCurrent == true then
		getSnackbarService():HideCurrent(options.doNotAnimate == true)
	end

	local snackbarOptions = if typeof(options.snackbarOptions) == "table"
		then (options.snackbarOptions :: { [string]: any })
		else nil

	return getSnackbarService():ShowSnackbar(text, snackbarOptions)
end

function NevermoreNotificationServiceClient.HideCurrent(doNotAnimateRaw: any)
	return getSnackbarService():HideCurrent(doNotAnimateRaw == true)
end

function NevermoreNotificationServiceClient.ClearQueue(doNotAnimateRaw: any)
	return getSnackbarService():ClearQueue(doNotAnimateRaw == true)
end

function NevermoreNotificationServiceClient.ShowBuildActionRejected(actionTypeRaw: any, reasonRaw: any)
	local actionType = string.lower(trim(actionTypeRaw))
	local reason = trim(reasonRaw)
	if actionType == "" then
		actionType = "place"
	end
	if reason == "" then
		reason = "generic"
	end

	local specificKey = `notifications.build.place.{reason}`
	local fallbackKey = "notifications.build.place.generic"
	if actionType == "break" then
		specificKey = `notifications.build.break.{reason}`
		fallbackKey = "notifications.build.break.generic"
	end

	local text = translate(specificKey) or translate(fallbackKey) or humanizeReason(reason)
	return NevermoreNotificationServiceClient.ShowText(text, {
		dedupeKey = `build:{actionType}:{reason}`,
		dedupeWindowSeconds = 0.45,
	})
end

function NevermoreNotificationServiceClient.ShowCraftResult(resultRaw: any, craftingServiceRaw: any)
	if typeof(resultRaw) ~= "table" then
		return nil
	end

	local result = resultRaw :: { [string]: any }
	if result.success == true then
		local quantity = 1
		if typeof(result.quantity) == "number" and result.quantity == result.quantity then
			quantity = math.max(1, math.floor(result.quantity))
		end

		local recipeName = resolveRecipeDisplayName(craftingServiceRaw, result.recipeId)
		local text = translate("notifications.crafting.success", {
			quantity = tostring(quantity),
			itemName = recipeName,
		}) or `Crafted {quantity}x {recipeName}`

		return NevermoreNotificationServiceClient.ShowText(text, {
			dedupeKey = `craft:success:{trim(result.recipeId)}`,
			dedupeWindowSeconds = 0.8,
		})
	end

	local reason = trim(result.reason)
	if reason == "" then
		reason = "generic"
	end

	local text = translate(`notifications.crafting.failure.{reason}`)
		or translate("notifications.crafting.failure.generic")
		or humanizeReason(reason)

	return NevermoreNotificationServiceClient.ShowText(text, {
		dedupeKey = `craft:failure:{reason}`,
		dedupeWindowSeconds = 0.8,
	})
end

NevermoreNotificationServiceClient.setScreenGui = NevermoreNotificationServiceClient.SetScreenGui
NevermoreNotificationServiceClient.showText = NevermoreNotificationServiceClient.ShowText
NevermoreNotificationServiceClient.hideCurrent = NevermoreNotificationServiceClient.HideCurrent
NevermoreNotificationServiceClient.clearQueue = NevermoreNotificationServiceClient.ClearQueue
NevermoreNotificationServiceClient.showBuildActionRejected = NevermoreNotificationServiceClient.ShowBuildActionRejected
NevermoreNotificationServiceClient.showCraftResult = NevermoreNotificationServiceClient.ShowCraftResult

return NevermoreNotificationServiceClient
