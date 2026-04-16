--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local PlayerDataServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.PlayerDataService.PlayerDataServiceUtils)

export type CoinType = "copper" | "silver" | "gold" | "platinum"
export type CoinAmounts = {
	copper: number,
	silver: number,
	gold: number,
	platinum: number,
}
export type CoinState = {
	loadState: PlayerDataServiceUtils.LoadState,
	amounts: CoinAmounts,
	totalCopper: number,
	updatedAt: number,
}

local COIN_VALUE_TO_COPPER: { [CoinType]: number } = {
	copper = 1,
	silver = 100,
	gold = 10_000,
	platinum = 1_000_000,
}

local COIN_TYPE_ORDER_DESCENDING: { CoinType } = { "platinum", "gold", "silver", "copper" }

local function sanitizeWholeNumber(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end

	return math.max(0, math.floor(valueRaw))
end

local function createDefaultCoinAmounts(): CoinAmounts
	return {
		copper = 0,
		silver = 0,
		gold = 0,
		platinum = 0,
	}
end

local function resolveRawCoinAmounts(coinsDataRaw: any): (CoinAmounts, boolean)
	if typeof(coinsDataRaw) ~= "table" then
		return createDefaultCoinAmounts(), false
	end

	local source = coinsDataRaw :: { [string]: any }
	local amounts: CoinAmounts = {
		copper = sanitizeWholeNumber(source.copper, 0),
		silver = sanitizeWholeNumber(source.silver, 0),
		gold = sanitizeWholeNumber(source.gold, 0),
		platinum = sanitizeWholeNumber(source.platinum, 0),
	}
	local hasExplicitAmounts = amounts.copper > 0 or amounts.silver > 0 or amounts.gold > 0 or amounts.platinum > 0
	return amounts, hasExplicitAmounts
end

local function coinsToTotalCopper(amounts: CoinAmounts): number
	return amounts.copper * COIN_VALUE_TO_COPPER.copper
		+ amounts.silver * COIN_VALUE_TO_COPPER.silver
		+ amounts.gold * COIN_VALUE_TO_COPPER.gold
		+ amounts.platinum * COIN_VALUE_TO_COPPER.platinum
end

local function totalCopperToCoinAmounts(totalCopperRaw: any): CoinAmounts
	local remaining = sanitizeWholeNumber(totalCopperRaw, 0)
	local amounts = createDefaultCoinAmounts()
	local amountMap = amounts :: { [CoinType]: number }

	for _, coinType in COIN_TYPE_ORDER_DESCENDING do
		local coinValue = COIN_VALUE_TO_COPPER[coinType]
		local coinCount = math.floor(remaining / coinValue)
		remaining -= coinCount * coinValue
		amountMap[coinType] = coinCount
	end

	return amounts
end

local function resolveTotalCopperFromCoinsData(coinsDataRaw: any, fallbackTotalCopper: number): number
	if typeof(coinsDataRaw) ~= "table" then
		return fallbackTotalCopper
	end

	local source = coinsDataRaw :: { [string]: any }
	local rawAmounts, hasExplicitAmounts = resolveRawCoinAmounts(source)
	if hasExplicitAmounts then
		return coinsToTotalCopper(rawAmounts)
	end

	local explicitTotalCopperRaw = source.totalCopper
	if typeof(explicitTotalCopperRaw) == "number" and explicitTotalCopperRaw == explicitTotalCopperRaw then
		return sanitizeWholeNumber(explicitTotalCopperRaw, fallbackTotalCopper)
	end

	return coinsToTotalCopper(rawAmounts)
end

local function createDefaultState(loadStateRaw: any): CoinState
	local amounts = createDefaultCoinAmounts()
	return {
		loadState = PlayerDataServiceUtils.sanitizeLoadState(loadStateRaw, PlayerDataServiceUtils.LOAD_STATE_UNLOADED),
		amounts = amounts,
		totalCopper = 0,
		updatedAt = os.clock(),
	}
end

local function createStateFromData(coinsDataRaw: any, loadStateRaw: any, fallbackStateRaw: any): CoinState
	local fallbackState = if typeof(fallbackStateRaw) == "table"
		then (fallbackStateRaw :: CoinState)
		else createDefaultState(PlayerDataServiceUtils.LOAD_STATE_UNLOADED)
	local loadState = PlayerDataServiceUtils.sanitizeLoadState(loadStateRaw, fallbackState.loadState)
	local rawAmounts, hasExplicitAmounts = resolveRawCoinAmounts(coinsDataRaw)
	local totalCopper = resolveTotalCopperFromCoinsData(coinsDataRaw, fallbackState.totalCopper)
	local amounts = if hasExplicitAmounts then rawAmounts else totalCopperToCoinAmounts(totalCopper)

	return {
		loadState = loadState,
		amounts = amounts,
		totalCopper = totalCopper,
		updatedAt = os.clock(),
	}
end

local coinStateAtom: Charm.Atom<CoinState> =
	Charm.atom(createDefaultState(PlayerDataServiceUtils.LOAD_STATE_UNLOADED))

local totalCopperAtom: Charm.Selector<number> = Charm.computed(function(): number
	return coinStateAtom().totalCopper
end)

local loadStateAtom: Charm.Selector<PlayerDataServiceUtils.LoadState> = Charm.computed(function()
	return coinStateAtom().loadState
end)

local function getCoinState(): CoinState
	return coinStateAtom()
end

local function setCoinState(stateRaw: any): CoinState
	local source = if typeof(stateRaw) == "table" then stateRaw else {}
	local sourceTable = source :: { [string]: any }
	local coinsData = if sourceTable.amounts ~= nil then sourceTable.amounts else sourceTable
	local nextState = createStateFromData(coinsData, sourceTable.loadState, coinStateAtom())
	coinStateAtom(nextState)
	return nextState
end

local function setCoinsData(coinsDataRaw: any, loadStateRaw: any): CoinState
	local nextState = createStateFromData(coinsDataRaw, loadStateRaw, coinStateAtom())
	coinStateAtom(nextState)
	return nextState
end

local function resetCoinState(): CoinState
	local nextState = createDefaultState(PlayerDataServiceUtils.LOAD_STATE_UNLOADED)
	coinStateAtom(nextState)
	return nextState
end

return {
	coinStateAtom = coinStateAtom,
	totalCopperAtom = totalCopperAtom,
	loadStateAtom = loadStateAtom,
	COIN_VALUE_TO_COPPER = COIN_VALUE_TO_COPPER,
	COIN_TYPE_ORDER_DESCENDING = COIN_TYPE_ORDER_DESCENDING,
	createDefaultCoinAmounts = createDefaultCoinAmounts,
	createDefaultState = createDefaultState,
	createStateFromData = createStateFromData,
	getCoinState = getCoinState,
	setCoinState = setCoinState,
	setCoinsData = setCoinsData,
	resetCoinState = resetCoinState,
}
