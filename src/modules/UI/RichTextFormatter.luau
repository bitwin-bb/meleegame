--!strict
local RichTextFormatter = {}

local Builder = {}
Builder.__index = Builder

export type FormatterConfig = {
	cacheLimit: number?,
	colorPresets: { [string]: Color3 | string }?,
}

export type Builder = {
	_append: (self: Builder, text: string) -> Builder,
	raw: (self: Builder, textRaw: any) -> Builder,
	append: (self: Builder, textRaw: any) -> Builder,
	line: (self: Builder, textRaw: any?) -> Builder,
	bold: (self: Builder, textRaw: any) -> Builder,
	italic: (self: Builder, textRaw: any) -> Builder,
	underline: (self: Builder, textRaw: any) -> Builder,
	font: (self: Builder, fontNameRaw: any, textRaw: any) -> Builder,
	size: (self: Builder, sizeRaw: any, textRaw: any) -> Builder,
	color: (self: Builder, colorRaw: any, textRaw: any) -> Builder,
	preset: (self: Builder, presetRaw: any, textRaw: any) -> Builder,
	gradient: (self: Builder, fromRaw: any, toRaw: any, textRaw: any) -> Builder,
	toString: (self: Builder, cacheKeyRaw: any?) -> string,
	clear: (self: Builder) -> Builder,
}

local globalCache = {
	values = {} :: { [string]: string },
	order = {} :: { string },
	limit = 2048,
}

local globalPresets = {
	white = Color3.fromRGB(255, 255, 255),
	black = Color3.fromRGB(0, 0, 0),
	red = Color3.fromRGB(255, 95, 95),
	green = Color3.fromRGB(95, 255, 140),
	blue = Color3.fromRGB(110, 190, 255),
	yellow = Color3.fromRGB(255, 235, 110),
	orange = Color3.fromRGB(255, 170, 90),
	gray = Color3.fromRGB(160, 160, 160),
	rarityCommon = Color3.fromRGB(220, 220, 220),
	rarityUncommon = Color3.fromRGB(110, 255, 140),
	rarityRare = Color3.fromRGB(90, 170, 255),
	rarityEpic = Color3.fromRGB(200, 120, 255),
	rarityLegendary = Color3.fromRGB(255, 190, 80),
}

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

local function clearArray(array: { any })
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

local function normalizeText(value: any): string
	if typeof(value) == "string" then
		return value
	end
	return tostring(value)
end

local function colorToHex(color: Color3): string
	local r = clampInteger(math.floor(color.R * 255 + 0.5), 255, 0, 255)
	local g = clampInteger(math.floor(color.G * 255 + 0.5), 255, 0, 255)
	local b = clampInteger(math.floor(color.B * 255 + 0.5), 255, 0, 255)
	return string.format("#%02X%02X%02X", r, g, b)
end

local function resolveColor(colorRaw: any): string?
	local kind = typeof(colorRaw)
	if kind == "Color3" then
		return colorToHex(colorRaw)
	end
	if kind == "string" then
		if string.match(colorRaw, "^#%x%x%x%x%x%x$") ~= nil then
			return string.upper(colorRaw)
		end
		local preset = globalPresets[colorRaw]
		if preset ~= nil then
			if typeof(preset) == "Color3" then
				return colorToHex(preset)
			end
			return preset
		end
	end
	return nil
end

local function interpolateColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function cachePut(key: string, value: string)
	if globalCache.values[key] ~= nil then
		globalCache.values[key] = value
		return
	end
	globalCache.values[key] = value
	globalCache.order[#globalCache.order + 1] = key
	while #globalCache.order > globalCache.limit do
		local oldest = table.remove(globalCache.order, 1)
		if oldest ~= nil then
			globalCache.values[oldest] = nil
		end
	end
end

function RichTextFormatter.escape(textRaw: any): string
	local text = normalizeText(textRaw)
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	text = string.gsub(text, '"', "&quot;")
	text = string.gsub(text, "'", "&apos;")
	return text
end

function RichTextFormatter.wrapTag(tag: string, contentRaw: any, attributesRaw: { [string]: any }?): string
	local content = RichTextFormatter.escape(contentRaw)
	if attributesRaw == nil or next(attributesRaw) == nil then
		return string.format("<%s>%s</%s>", tag, content, tag)
	end
	local parts = {}
	for key, value in attributesRaw do
		parts[#parts + 1] = string.format('%s="%s"', key, tostring(value))
	end
	table.sort(parts)
	return string.format("<%s %s>%s</%s>", tag, table.concat(parts, " "), content, tag)
end

function RichTextFormatter.new(configRaw: FormatterConfig?): Builder
	local config = if typeof(configRaw) == "table" then configRaw else {}
	if typeof(config.cacheLimit) == "number" then
		globalCache.limit = clampInteger(config.cacheLimit, globalCache.limit, 8, 100000)
	end
	if typeof(config.colorPresets) == "table" then
		for key, value in config.colorPresets do
			if typeof(key) == "string" and (typeof(value) == "Color3" or typeof(value) == "string") then
				globalPresets[key] = value
			end
		end
	end
	return setmetatable({
		parts = {} :: { string },
	}, Builder)
end

function Builder._append(self: Builder, text: string): Builder
	self.parts[#self.parts + 1] = text
	return self
end

function Builder.append(self: Builder, textRaw: any): Builder
	return self:_append(RichTextFormatter.escape(textRaw))
end

function Builder.raw(self: Builder, textRaw: any): Builder
	return self:_append(normalizeText(textRaw))
end

function Builder.line(self: Builder, textRaw: any?): Builder
	if textRaw ~= nil then
		self:append(textRaw)
	end
	return self:_append("\n")
end

function Builder.bold(self: Builder, textRaw: any): Builder
	return self:_append(RichTextFormatter.wrapTag("b", textRaw))
end

function Builder.italic(self: Builder, textRaw: any): Builder
	return self:_append(RichTextFormatter.wrapTag("i", textRaw))
end

function Builder.underline(self: Builder, textRaw: any): Builder
	return self:_append(RichTextFormatter.wrapTag("u", textRaw))
end

function Builder.font(self: Builder, fontNameRaw: any, textRaw: any): Builder
	local fontName = normalizeText(fontNameRaw)
	return self:_append(RichTextFormatter.wrapTag("font", textRaw, { face = fontName }))
end

function Builder.size(self: Builder, sizeRaw: any, textRaw: any): Builder
	local size = clampInteger(sizeRaw, 14, 1, 256)
	return self:_append(RichTextFormatter.wrapTag("font", textRaw, { size = tostring(size) }))
end

function Builder.color(self: Builder, colorRaw: any, textRaw: any): Builder
	local colorHex = resolveColor(colorRaw)
	if colorHex == nil then
		return self:append(textRaw)
	end
	return self:_append(RichTextFormatter.wrapTag("font", textRaw, { color = colorHex }))
end

function Builder.preset(self: Builder, presetRaw: any, textRaw: any): Builder
	return self:color(presetRaw, textRaw)
end

function Builder.gradient(self: Builder, fromRaw: any, toRaw: any, textRaw: any): Builder
	local text = normalizeText(textRaw)
	if text == "" then
		return self
	end
	local fromColor = if typeof(fromRaw) == "Color3" then fromRaw else Color3.fromRGB(255, 255, 255)
	local toColor = if typeof(toRaw) == "Color3" then toRaw else fromColor
	local charCount = utf8.len(text) or #text
	if charCount <= 1 then
		return self:color(fromColor, text)
	end
	local charIndex = 0
	for char in string.gmatch(text, utf8.charpattern) do
		charIndex += 1
		local t = (charIndex - 1) / (charCount - 1)
		local colorHex = colorToHex(interpolateColor(fromColor, toColor, t))
		self:_append(RichTextFormatter.wrapTag("font", char, { color = colorHex }))
	end
	return self
end

function Builder.toString(self: Builder, cacheKeyRaw: any?): string
	local cacheKey = if typeof(cacheKeyRaw) == "string" and cacheKeyRaw ~= "" then cacheKeyRaw else nil
	if cacheKey ~= nil then
		local cached = globalCache.values[cacheKey]
		if cached ~= nil then
			return cached
		end
	end
	local output = table.concat(self.parts)
	if cacheKey ~= nil then
		cachePut(cacheKey, output)
	end
	return output
end

function Builder.clear(self: Builder): Builder
	clearArray(self.parts)
	return self
end

function RichTextFormatter.formatCached(cacheKeyRaw: any, producer: () -> string): string
	if typeof(cacheKeyRaw) ~= "string" or cacheKeyRaw == "" then
		return producer()
	end
	local cached = globalCache.values[cacheKeyRaw]
	if cached ~= nil then
		return cached
	end
	local output = producer()
	cachePut(cacheKeyRaw, output)
	return output
end

function RichTextFormatter.setColorPreset(nameRaw: any, valueRaw: any): boolean
	if typeof(nameRaw) ~= "string" or nameRaw == "" then
		return false
	end
	if typeof(valueRaw) ~= "Color3" and typeof(valueRaw) ~= "string" then
		return false
	end
	globalPresets[nameRaw] = valueRaw
	return true
end

function RichTextFormatter.getColorPreset(nameRaw: any): any
	if typeof(nameRaw) ~= "string" then
		return nil
	end
	return globalPresets[nameRaw]
end

function RichTextFormatter.clearCache()
	table.clear(globalCache.values)
	clearArray(globalCache.order)
end

return RichTextFormatter
