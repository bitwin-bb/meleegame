--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AbbreviationFormatter = require(script.Parent.AbbreviationFormatter)

local DynamicTextResolver = {}
DynamicTextResolver.__index = DynamicTextResolver

export type ResolverConfig = {
	maxDepth: number?,
	keepUnknownPlaceholders: boolean?,
	missingValue: string?,
	warnOnMissing: boolean?,
	onMissing: ((key: string, template: string) -> ())?,
}

export type ResolveOptions = {
	keepUnknownPlaceholders: boolean?,
	missingValue: string?,
	maxDepth: number?,
}

export type DynamicTextResolver = typeof(setmetatable({} :: any, DynamicTextResolver))

local function clampInteger(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then math.floor(valueRaw) else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function splitPath(path: string): { string }
	local out = {}
	local startIndex = 1
	while startIndex <= #path do
		local dotIndex = string.find(path, ".", startIndex, true)
		if dotIndex == nil then
			out[#out + 1] = string.sub(path, startIndex)
			break
		end
		out[#out + 1] = string.sub(path, startIndex, dotIndex - 1)
		startIndex = dotIndex + 1
	end
	return out
end

local function resolvePath(context: any, keyPath: string): any
	if typeof(context) ~= "table" then
		return nil
	end
	if keyPath == "" then
		return nil
	end
	local cursor = context
	for _, segment in splitPath(keyPath) do
		if typeof(cursor) ~= "table" then
			return nil
		end
		cursor = cursor[segment]
		if cursor == nil then
			return nil
		end
	end
	return cursor
end

local function isTruthy(value: any): boolean
	if value == nil then
		return false
	end
	if typeof(value) == "boolean" then
		return value
	end
	return true
end

local function toStringValue(value: any): string
	local kind = typeof(value)
	if kind == "string" then
		return value
	end
	if kind == "number" then
		return AbbreviationFormatter.formatNumber(value)
	end
	if kind == "boolean" then
		return if value then "true" else "false"
	end
	return tostring(value)
end

function DynamicTextResolver.New(configRaw: ResolverConfig?): DynamicTextResolver
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		maxDepth = clampInteger(config.maxDepth, 4, 1, 20),
		keepUnknownPlaceholders = if config.keepUnknownPlaceholders == nil then true else config.keepUnknownPlaceholders == true,
		missingValue = if typeof(config.missingValue) == "string" then config.missingValue else "",
		warnOnMissing = config.warnOnMissing == true,
		onMissing = config.onMissing,
	}, DynamicTextResolver)
	return self
end

function DynamicTextResolver._missing(self: DynamicTextResolver, key: string, template: string, keepUnknown: boolean, missingValue: string): string
	if self.onMissing ~= nil then
		self.onMissing(key, template)
	end
	if keepUnknown then
		return "{" .. key .. "}"
	end
	return missingValue
end

function DynamicTextResolver._applyModifier(self: DynamicTextResolver, value: any, modifierRaw: string): string
	if modifierRaw == "" then
		return toStringValue(value)
	end

	local modifier = modifierRaw
	local arg = ""
	local separator = string.find(modifierRaw, ",", 1, true)
	if separator ~= nil then
		modifier = string.sub(modifierRaw, 1, separator - 1)
		arg = string.sub(modifierRaw, separator + 1)
	end

	if modifier == "abbr" or modifier == "number" then
		return AbbreviationFormatter.formatNumber(value)
	end
	if modifier == "percent" then
		return AbbreviationFormatter.formatPercent(value)
	end
	if modifier == "dps" then
		return AbbreviationFormatter.formatDps(value)
	end
	if modifier == "time" then
		return AbbreviationFormatter.formatTime(value)
	end
	if modifier == "mmss" then
		return AbbreviationFormatter.formatTimeMMSS(value)
	end
	if modifier == "upper" then
		return string.upper(toStringValue(value))
	end
	if modifier == "lower" then
		return string.lower(toStringValue(value))
	end
	if modifier == "fixed" then
		local precision = tonumber(arg) or 2
		if typeof(value) ~= "number" then
			return toStringValue(value)
		end
		return string.format("%.*f", math.max(0, math.floor(precision)), value)
	end

	local fixedDigits = string.match(modifier, "^fixed(%d+)$")
	if fixedDigits ~= nil then
		if typeof(value) ~= "number" then
			return toStringValue(value)
		end
		local precision = math.max(0, math.floor(tonumber(fixedDigits) or 0))
		return string.format("%.*f", precision, value)
	end

	return toStringValue(value)
end

function DynamicTextResolver._resolveConditionals(
	self: DynamicTextResolver,
	template: string,
	context: { [string]: any },
	depth: number,
	options: ResolveOptions
): string
	local resolved = template
	local changed = true
	local guard = 0
	while changed do
		changed = false
		guard += 1
		if guard > 32 then
			break
		end

		local nextText = string.gsub(resolved, "%[if:([%w_%.]+)%](.-)%[/if%]", function(key: string, body: string)
			changed = true
			local value = resolvePath(context, key)
			if isTruthy(value) then
				return self:_resolveInternal(body, context, depth + 1, options)
			end
			return ""
		end)
		resolved = nextText

		nextText = string.gsub(resolved, "%[ifnot:([%w_%.]+)%](.-)%[/ifnot%]", function(key: string, body: string)
			changed = true
			local value = resolvePath(context, key)
			if not isTruthy(value) then
				return self:_resolveInternal(body, context, depth + 1, options)
			end
			return ""
		end)
		resolved = nextText
	end

	return resolved
end

function DynamicTextResolver._resolveInternal(
	self: DynamicTextResolver,
	templateRaw: string,
	contextRaw: { [string]: any }?,
	depth: number,
	optionsRaw: ResolveOptions?
): string
	if typeof(templateRaw) ~= "string" then
		return ""
	end
	local context = if typeof(contextRaw) == "table" then contextRaw else {}
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local maxDepth = clampInteger(options.maxDepth, self.maxDepth, 1, 20)
	if depth >= maxDepth then
		return templateRaw
	end

	local keepUnknown = if options.keepUnknownPlaceholders == nil then self.keepUnknownPlaceholders else options.keepUnknownPlaceholders == true
	local missingValue = if typeof(options.missingValue) == "string" then options.missingValue else self.missingValue

	local conditioned = self:_resolveConditionals(templateRaw, context, depth, options)
	local didReplace = false
	local resolved = string.gsub(conditioned, "{([^{}]+)}", function(token: string)
		local key = token
		local modifier = ""
		local separator = string.find(token, ":", 1, true)
		if separator ~= nil then
			key = string.sub(token, 1, separator - 1)
			modifier = string.sub(token, separator + 1)
		end
		if key == "" then
			return ""
		end
		local value = resolvePath(context, key)
		if value == nil then
			return self:_missing(key, templateRaw, keepUnknown, missingValue)
		end
		didReplace = true
		return self:_applyModifier(value, modifier)
	end)

	if didReplace and string.find(resolved, "{", 1, true) ~= nil then
		return self:_resolveInternal(resolved, context, depth + 1, options)
	end
	return resolved
end

function DynamicTextResolver.Resolve(self: DynamicTextResolver, templateRaw: any, contextRaw: any, optionsRaw: ResolveOptions?): string
	if typeof(templateRaw) ~= "string" then
		return ""
	end
	local context = if typeof(contextRaw) == "table" then contextRaw else {}
	return self:_resolveInternal(templateRaw, context, 0, optionsRaw)
end

function DynamicTextResolver.ResolveMany(self: DynamicTextResolver, templatesRaw: any, contextRaw: any, outRaw: { string }?): { string }
	local out = if outRaw ~= nil then outRaw else {}
	if typeof(templatesRaw) ~= "table" then
		table.clear(out)
		return out
	end
	local context = if typeof(contextRaw) == "table" then contextRaw else {}
	table.clear(out)
	for index = 1, #templatesRaw do
		out[index] = self:resolve(templatesRaw[index], context)
	end
	for index = #out, #templatesRaw + 1, -1 do
		out[index] = nil
	end
	return out
end

DynamicTextResolver.new = DynamicTextResolver.New
DynamicTextResolver.resolve = DynamicTextResolver.Resolve
DynamicTextResolver.resolveMany = DynamicTextResolver.ResolveMany

return DynamicTextResolver
