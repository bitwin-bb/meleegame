--!strict
local DynamicTextResolver = require(script.Parent.DynamicTextResolver)

local LocalizationEngine = {}
LocalizationEngine.__index = LocalizationEngine

export type TranslationValue = string | { [string]: string }
export type LanguageTable = { [string]: TranslationValue }

export type LocalizationConfig = {
	defaultLanguage: string?,
	fallbackLanguage: string?,
	warnOnMissing: boolean?,
	resolver: any?,
}

export type TranslateOptions = {
	language: string?,
	fallbackLanguage: string?,
	count: number?,
}

export type LocalizationEngine = typeof(setmetatable({} :: any, LocalizationEngine))

local DEFAULT_PLURAL_RULE = function(count: number): string
	if count == 1 then
		return "one"
	end
	return "other"
end

local function isValidLanguageCode(codeRaw: any): boolean
	return typeof(codeRaw) == "string" and codeRaw ~= ""
end

local function normalizeCount(countRaw: any): number
	if typeof(countRaw) ~= "number" then
		return 0
	end
	return math.floor(countRaw)
end

function LocalizationEngine.New(configRaw: LocalizationConfig?): LocalizationEngine
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local defaultLanguage = if isValidLanguageCode(config.defaultLanguage) then config.defaultLanguage else "en"
	local fallbackLanguage = if isValidLanguageCode(config.fallbackLanguage) then config.fallbackLanguage else defaultLanguage
	local resolver = if config.resolver ~= nil then config.resolver else DynamicTextResolver.new({
		warnOnMissing = false,
		keepUnknownPlaceholders = true,
	})

	local self = setmetatable({
		languages = {} :: { [string]: LanguageTable },
		pluralRules = {} :: { [string]: (count: number) -> string },
		currentLanguage = defaultLanguage,
		defaultLanguage = defaultLanguage,
		fallbackLanguage = fallbackLanguage,
		warnOnMissing = config.warnOnMissing == true,
		resolver = resolver,
	}, LocalizationEngine)
	return self
end

function LocalizationEngine.RegisterLanguage(self: LocalizationEngine, languageRaw: any, tableRaw: any): boolean
	if not isValidLanguageCode(languageRaw) then
		return false
	end
	if typeof(tableRaw) ~= "table" then
		return false
	end
	local language = languageRaw :: string
	local copy = {}
	for key, value in tableRaw do
		if typeof(key) ~= "string" then
			continue
		end
		if typeof(value) == "string" then
			copy[key] = value
		elseif typeof(value) == "table" then
			local forms = {}
			for form, text in value do
				if typeof(form) == "string" and typeof(text) == "string" then
					forms[form] = text
				end
			end
			copy[key] = forms
		end
	end
	self.languages[language] = copy
	if self.pluralRules[language] == nil then
		self.pluralRules[language] = DEFAULT_PLURAL_RULE
	end
	return true
end

function LocalizationEngine.RegisterLanguages(self: LocalizationEngine, tablesRaw: any)
	if typeof(tablesRaw) ~= "table" then
		return
	end
	for language, languageTable in tablesRaw do
		if typeof(language) == "string" then
			self:registerLanguage(language, languageTable)
		end
	end
end

function LocalizationEngine.SetPluralRule(self: LocalizationEngine, languageRaw: any, callbackRaw: any): boolean
	if not isValidLanguageCode(languageRaw) then
		return false
	end
	if typeof(callbackRaw) ~= "function" then
		return false
	end
	self.pluralRules[languageRaw] = callbackRaw
	return true
end

function LocalizationEngine.SetLanguage(self: LocalizationEngine, languageRaw: any): boolean
	if not isValidLanguageCode(languageRaw) then
		return false
	end
	if self.languages[languageRaw] == nil then
		return false
	end
	self.currentLanguage = languageRaw
	return true
end

function LocalizationEngine.GetLanguage(self: LocalizationEngine): string
	return self.currentLanguage
end

function LocalizationEngine.GetAvailableLanguages(self: LocalizationEngine): { string }
	local out = {}
	for language in self.languages do
		out[#out + 1] = language
	end
	table.sort(out)
	return out
end

function LocalizationEngine._resolvePlural(self: LocalizationEngine, language: string, value: { [string]: string }, countRaw: any): string?
	local count = normalizeCount(countRaw)
	local rule = self.pluralRules[language] or DEFAULT_PLURAL_RULE
	local form = rule(count)
	local selected = value[form]
	if selected ~= nil then
		return selected
	end
	if count == 0 and value.zero ~= nil then
		return value.zero
	end
	if count == 1 and value.one ~= nil then
		return value.one
	end
	return value.other
end

function LocalizationEngine._lookup(self: LocalizationEngine, language: string, key: string, countRaw: any): string?
	local languageTable = self.languages[language]
	if languageTable == nil then
		return nil
	end
	local entry = languageTable[key]
	if entry == nil then
		return nil
	end
	if typeof(entry) == "string" then
		return entry
	end
	if typeof(entry) == "table" then
		return self:_resolvePlural(language, entry :: { [string]: string }, countRaw)
	end
	return nil
end

function LocalizationEngine.Translate(self: LocalizationEngine, keyRaw: any, paramsRaw: any?, optionsRaw: TranslateOptions?): string
	if typeof(keyRaw) ~= "string" or keyRaw == "" then
		return ""
	end
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local params = if typeof(paramsRaw) == "table" then paramsRaw else {}
	local language = if isValidLanguageCode(options.language) then options.language else self.currentLanguage
	local fallbackLanguage = if isValidLanguageCode(options.fallbackLanguage) then options.fallbackLanguage else self.fallbackLanguage

	local count = if options.count ~= nil then options.count else params.count
	local template = self:_lookup(language, keyRaw, count)
	if template == nil and fallbackLanguage ~= language then
		template = self:_lookup(fallbackLanguage, keyRaw, count)
	end
	if template == nil and self.defaultLanguage ~= language and self.defaultLanguage ~= fallbackLanguage then
		template = self:_lookup(self.defaultLanguage, keyRaw, count)
	end
	if template == nil then
		return keyRaw
	end

	return self.resolver:resolve(template, params)
end

function LocalizationEngine.ValidateLanguage(self: LocalizationEngine, languageRaw: any): { string }
	local errors = {}
	if not isValidLanguageCode(languageRaw) then
		errors[#errors + 1] = "Language code is invalid"
		return errors
	end
	local languageTable = self.languages[languageRaw]
	if languageTable == nil then
		errors[#errors + 1] = string.format("Language '%s' is not registered", languageRaw)
		return errors
	end
	for key, value in languageTable do
		if typeof(key) ~= "string" then
			errors[#errors + 1] = "Found non-string translation key"
			continue
		end
		if typeof(value) == "string" then
			continue
		end
		if typeof(value) ~= "table" then
			errors[#errors + 1] = string.format("Key '%s' has invalid value type", key)
			continue
		end
		if value.other == nil and value.one == nil then
			errors[#errors + 1] = string.format("Key '%s' missing plural forms (expected 'other' or 'one')", key)
		end
	end
	return errors
end

function LocalizationEngine.HasKey(self: LocalizationEngine, keyRaw: any, languageRaw: any?): boolean
	if typeof(keyRaw) ~= "string" then
		return false
	end
	local language = if isValidLanguageCode(languageRaw) then languageRaw else self.currentLanguage
	local languageTable = self.languages[language]
	if languageTable == nil then
		return false
	end
	return languageTable[keyRaw] ~= nil
end

LocalizationEngine.new = LocalizationEngine.New
LocalizationEngine.registerLanguage = LocalizationEngine.RegisterLanguage
LocalizationEngine.registerLanguages = LocalizationEngine.RegisterLanguages
LocalizationEngine.setPluralRule = LocalizationEngine.SetPluralRule
LocalizationEngine.setLanguage = LocalizationEngine.SetLanguage
LocalizationEngine.getLanguage = LocalizationEngine.GetLanguage
LocalizationEngine.getAvailableLanguages = LocalizationEngine.GetAvailableLanguages
LocalizationEngine.translate = LocalizationEngine.Translate
LocalizationEngine.validateLanguage = LocalizationEngine.ValidateLanguage
LocalizationEngine.hasKey = LocalizationEngine.HasKey

return LocalizationEngine
