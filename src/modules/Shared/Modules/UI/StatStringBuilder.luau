--!strict
local AbbreviationFormatter = require(script.Parent.AbbreviationFormatter)
local RichTextFormatter = require(script.Parent.RichTextFormatter)

local StatStringBuilder = {}
StatStringBuilder.__index = StatStringBuilder

export type StatDefinition = {
	id: string,
	label: string?,
	format: string?,
	precision: number?,
	hidden: boolean?,
	inverseDelta: boolean?,
	showSign: boolean?,
	showBreakdown: boolean?,
}

export type ModifierBreakdown = {
	base: number?,
	additive: number?,
	multiplicative: number?,
}

export type StatToken = {
	kind: "label" | "value" | "delta" | "separator" | "breakdown" | "newline",
	statId: string,
	text: string,
	color: string?,
}

export type BuilderConfig = {
	attributeCache: any?,
	positiveColor: string?,
	negativeColor: string?,
	neutralColor: string?,
}

export type BuildOptions = {
	includeHidden: boolean?,
	showUnchanged: boolean?,
	deltaThreshold: number?,
	returnRichText: boolean?,
}

export type StatStringBuilder = typeof(setmetatable({} :: any, StatStringBuilder))

local function clampNumber(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then valueRaw else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function toNumber(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" then
		return fallback
	end
	return valueRaw
end

local function resolveDefinition(defRaw: any, statId: string): StatDefinition
	if typeof(defRaw) ~= "table" then
		return {
			id = statId,
			label = statId,
		}
	end
	return {
		id = statId,
		label = if typeof(defRaw.label) == "string" then defRaw.label else statId,
		format = if typeof(defRaw.format) == "string" then defRaw.format else nil,
		precision = if typeof(defRaw.precision) == "number" then math.floor(defRaw.precision) else nil,
		hidden = defRaw.hidden == true,
		inverseDelta = defRaw.inverseDelta == true,
		showSign = defRaw.showSign == true,
		showBreakdown = defRaw.showBreakdown == true,
	}
end

local function autoDetectFormat(statId: string, value: number): string
	local lowered = string.lower(statId)
	if string.find(lowered, "percent", 1, true) ~= nil or string.find(lowered, "chance", 1, true) ~= nil or string.find(lowered, "crit", 1, true) ~= nil then
		return "percent"
	end
	if string.find(lowered, "dps", 1, true) ~= nil then
		return "dps"
	end
	if string.find(lowered, "time", 1, true) ~= nil or string.find(lowered, "cooldown", 1, true) ~= nil then
		return "time"
	end
	if math.abs(value) <= 1 then
		return "percent"
	end
	return "number"
end

local function sortDefinitions(definitions: { StatDefinition })
	table.sort(definitions, function(a, b)
		return a.id < b.id
	end)
end

function StatStringBuilder.New(configRaw: BuilderConfig?): StatStringBuilder
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		attributeCache = config.attributeCache,
		positiveColor = if typeof(config.positiveColor) == "string" then config.positiveColor else "green",
		negativeColor = if typeof(config.negativeColor) == "string" then config.negativeColor else "red",
		neutralColor = if typeof(config.neutralColor) == "string" then config.neutralColor else "gray",
	}, StatStringBuilder)
	return self
end

function StatStringBuilder._read(self: StatStringBuilder, source: any, statId: string): any
	if source == nil then
		return nil
	end
	if typeof(source) == "table" then
		return source[statId]
	end
	if typeof(source) == "Instance" then
		if self.attributeCache ~= nil and typeof(self.attributeCache.get) == "function" then
			return self.attributeCache:get(source, statId, source:GetAttribute(statId))
		end
		return source:GetAttribute(statId)
	end
	return nil
end

function StatStringBuilder._formatValue(self: StatStringBuilder, statId: string, valueRaw: any, formatRaw: any, precisionRaw: any): string
	local value = toNumber(valueRaw, 0)
	local formatKind = if typeof(formatRaw) == "string" then formatRaw else autoDetectFormat(statId, value)
	return AbbreviationFormatter.formatValue(value, formatKind, precisionRaw)
end

function StatStringBuilder._normalizeDefinitions(self: StatStringBuilder, definitionsRaw: any, currentSource: any): { StatDefinition }
	local definitions = {}
	if typeof(definitionsRaw) == "table" and #definitionsRaw > 0 then
		for _, defRaw in definitionsRaw do
			if typeof(defRaw) == "table" and typeof(defRaw.id) == "string" then
				definitions[#definitions + 1] = resolveDefinition(defRaw, defRaw.id)
			end
		end
	else
		if typeof(currentSource) == "table" then
			for key in currentSource do
				if typeof(key) == "string" then
					definitions[#definitions + 1] = resolveDefinition(nil, key)
				end
			end
		elseif typeof(currentSource) == "Instance" then
			local attributes = currentSource:GetAttributes()
			for key in attributes do
				if typeof(key) == "string" then
					definitions[#definitions + 1] = resolveDefinition(nil, key)
				end
			end
		end
	end
	sortDefinitions(definitions)
	return definitions
end

function StatStringBuilder.BuildTokens(
	self: StatStringBuilder,
	currentSource: any,
	compareSource: any?,
	definitionsRaw: any?,
	modifierBreakdownRaw: any?,
	optionsRaw: BuildOptions?
): { StatToken }
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local includeHidden = options.includeHidden == true
	local showUnchanged = if options.showUnchanged == nil then true else options.showUnchanged == true
	local deltaThreshold = clampNumber(options.deltaThreshold, 0, 0, 1e9)
	local modifierBreakdown = if typeof(modifierBreakdownRaw) == "table" then modifierBreakdownRaw else {}

	local definitions = self:_normalizeDefinitions(definitionsRaw, currentSource)
	local tokens = {}
	for index = 1, #definitions do
		local definition = definitions[index]
		if definition.hidden and not includeHidden then
			continue
		end
		local statId = definition.id
		local currentValue = toNumber(self:_read(currentSource, statId), 0)
		local compareValue = self:_read(compareSource, statId)
		local hasCompare = compareValue ~= nil and typeof(compareValue) == "number"
		local delta = if hasCompare then currentValue - (compareValue :: number) else 0

		if hasCompare and not showUnchanged and math.abs(delta) <= deltaThreshold then
			continue
		end

		tokens[#tokens + 1] = {
			kind = "label",
			statId = statId,
			text = (definition.label or statId) .. ": ",
			color = nil,
		}
		tokens[#tokens + 1] = {
			kind = "value",
			statId = statId,
			text = self:_formatValue(statId, currentValue, definition.format, definition.precision),
			color = nil,
		}

		if hasCompare then
			local deltaColor = self.neutralColor
			if math.abs(delta) > deltaThreshold then
				local positive = delta > 0
				if definition.inverseDelta then
					positive = not positive
				end
				deltaColor = if positive then self.positiveColor else self.negativeColor
			end
			local deltaText = self:_formatValue(statId, math.abs(delta), definition.format, definition.precision)
			local sign = if delta > 0 then "+" else if delta < 0 then "-" else ""
			tokens[#tokens + 1] = {
				kind = "separator",
				statId = statId,
				text = " ",
				color = nil,
			}
			tokens[#tokens + 1] = {
				kind = "delta",
				statId = statId,
				text = "(" .. sign .. deltaText .. ")",
				color = deltaColor,
			}
		end

		if definition.showBreakdown then
			local breakdown = modifierBreakdown[statId]
			if typeof(breakdown) == "table" then
				local base = toNumber(breakdown.base, 0)
				local add = toNumber(breakdown.additive, 0)
				local mul = toNumber(breakdown.multiplicative, 1)
				local breakdownText = string.format(" [base %s, +%s, x%s]", AbbreviationFormatter.formatNumber(base), AbbreviationFormatter.formatNumber(add), AbbreviationFormatter.formatNumber(mul))
				tokens[#tokens + 1] = {
					kind = "breakdown",
					statId = statId,
					text = breakdownText,
					color = self.neutralColor,
				}
			end
		end

		if index < #definitions then
			tokens[#tokens + 1] = {
				kind = "newline",
				statId = statId,
				text = "\n",
				color = nil,
			}
		end
	end
	return tokens
end

function StatStringBuilder.TokensToRichText(self: StatStringBuilder, tokensRaw: any): string
	if typeof(tokensRaw) ~= "table" then
		return ""
	end
	local builder = RichTextFormatter.new()
	for index = 1, #tokensRaw do
		local token = tokensRaw[index]
		if typeof(token) ~= "table" then
			continue
		end
		if token.kind == "newline" then
			builder:line()
			continue
		end
		if typeof(token.color) == "string" and token.color ~= "" then
			builder:preset(token.color, token.text)
		else
			builder:append(token.text)
		end
	end
	return builder:toString()
end

function StatStringBuilder.BuildRichText(
	self: StatStringBuilder,
	currentSource: any,
	compareSource: any?,
	definitionsRaw: any?,
	modifierBreakdownRaw: any?,
	optionsRaw: BuildOptions?
): string
	local tokens = self:buildTokens(currentSource, compareSource, definitionsRaw, modifierBreakdownRaw, optionsRaw)
	return self:tokensToRichText(tokens)
end

StatStringBuilder.new = StatStringBuilder.New
StatStringBuilder.buildTokens = StatStringBuilder.BuildTokens
StatStringBuilder.tokensToRichText = StatStringBuilder.TokensToRichText
StatStringBuilder.buildRichText = StatStringBuilder.BuildRichText

return StatStringBuilder
