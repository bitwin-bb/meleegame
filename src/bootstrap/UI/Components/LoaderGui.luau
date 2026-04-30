--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PACKAGES_NAME = "Packages"
local REACT_NAME = "React"
local PACKAGE_WAIT_TIMEOUT_SECONDS = 60

local LOADER_FONT = Enum.Font.Code
local BACKGROUND_COLOR = Color3.fromRGB(0, 0, 0)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local TRACK_COLOR = Color3.fromRGB(46, 46, 46)
local BAR_COLOR = Color3.fromRGB(255, 255, 255)

local function waitForPackageModule(name: string): ModuleScript
	local packages = ReplicatedStorage:WaitForChild(PACKAGES_NAME, PACKAGE_WAIT_TIMEOUT_SECONDS)
	if packages == nil then
		error(`timed out waiting for ReplicatedStorage.{PACKAGES_NAME}`)
	end

	local module = packages:WaitForChild(name, PACKAGE_WAIT_TIMEOUT_SECONDS)
	if module == nil or not module:IsA("ModuleScript") then
		error(`timed out waiting for ReplicatedStorage.{PACKAGES_NAME}.{name}`)
	end

	return module
end

local React = require(waitForPackageModule(REACT_NAME))
local e: typeof(React.createElement) = React.createElement

export type LoaderSnapshot = {
	status: string,
	stage: string,
	message: string,
	progress: number,
	completed: number,
	total: number,
	startedAt: number,
	finishedAt: number?,
	moduleCount: number,
	assetCount: number,
	assetLoadedCount: number,
	assetFailedCount: number,
	failureCount: number,
	lastError: string?,
	failures: { string },
}

export type LoaderGuiProps = {
	snapshot: LoaderSnapshot?,
}

local DEFAULT_SNAPSHOT: LoaderSnapshot = {
	status = "idle",
	stage = "boot",
	message = "starting loader",
	progress = 0,
	completed = 0,
	total = 100,
	startedAt = 0,
	finishedAt = nil,
	moduleCount = 0,
	assetCount = 0,
	assetLoadedCount = 0,
	assetFailedCount = 0,
	failureCount = 0,
	lastError = nil,
	failures = {},
}

local LOADING_TEXT_BY_STAGE: { [string]: string } = {
	boot = "starting loader",
	replication = "loading world package",
	framework = "loading framework",
	network = "connecting network",
	packages = "loading runtime packages",
	modules = "loading game modules",
	data = "generating world data",
	assets = "preloading content",
	chunks = "preloading world chunks",
	scripts = "preparing client scripts",
	complete = "entering world",
	failed = "loader failed",
}

local function sanitizeNumber(value: any, fallback: number, minimum: number?, maximum: number?): number
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end

	local nextValue = value
	if minimum ~= nil and nextValue < minimum then
		nextValue = minimum
	end
	if maximum ~= nil and nextValue > maximum then
		nextValue = maximum
	end
	return nextValue
end

local function sanitizeString(value: any, fallback: string): string
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function sanitizeStringArray(valueRaw: any): { string }
	local values: { string } = {}
	if typeof(valueRaw) ~= "table" then
		return values
	end

	for _, value in valueRaw do
		if typeof(value) == "string" then
			values[#values + 1] = value
		end
	end

	return values
end

local function sanitizeSnapshot(valueRaw: any): LoaderSnapshot
	local value: { [string]: any } = if typeof(valueRaw) == "table" then valueRaw :: { [string]: any } else {}

	return {
		status = sanitizeString(value.status, DEFAULT_SNAPSHOT.status),
		stage = sanitizeString(value.stage, DEFAULT_SNAPSHOT.stage),
		message = sanitizeString(value.message, DEFAULT_SNAPSHOT.message),
		progress = sanitizeNumber(value.progress, DEFAULT_SNAPSHOT.progress, 0, 1),
		completed = sanitizeNumber(value.completed, DEFAULT_SNAPSHOT.completed, 0, nil),
		total = sanitizeNumber(value.total, DEFAULT_SNAPSHOT.total, 1, nil),
		startedAt = sanitizeNumber(value.startedAt, DEFAULT_SNAPSHOT.startedAt, 0, nil),
		finishedAt = if typeof(value.finishedAt) == "number" then value.finishedAt else nil,
		moduleCount = sanitizeNumber(value.moduleCount, DEFAULT_SNAPSHOT.moduleCount, 0, nil),
		assetCount = sanitizeNumber(value.assetCount, DEFAULT_SNAPSHOT.assetCount, 0, nil),
		assetLoadedCount = sanitizeNumber(value.assetLoadedCount, DEFAULT_SNAPSHOT.assetLoadedCount, 0, nil),
		assetFailedCount = sanitizeNumber(value.assetFailedCount, DEFAULT_SNAPSHOT.assetFailedCount, 0, nil),
		failureCount = sanitizeNumber(value.failureCount, DEFAULT_SNAPSHOT.failureCount, 0, nil),
		lastError = if typeof(value.lastError) == "string" and value.lastError ~= "" then value.lastError else nil,
		failures = sanitizeStringArray(value.failures),
	}
end

local function resolveLoadingText(snapshot: LoaderSnapshot): string
	if snapshot.status == "failed" then
		return "loader failed"
	end

	local stageText = LOADING_TEXT_BY_STAGE[snapshot.stage]
	if stageText ~= nil then
		return stageText
	end

	return sanitizeString(snapshot.message, "loading world")
end

local function formatPercent(progress: number): string
	return `{math.floor(math.clamp(progress, 0, 1) * 100 + 0.5)}%`
end

local function LoaderGui(props: LoaderGuiProps): React.ReactNode
	local snapshot = sanitizeSnapshot(props.snapshot)
	local progress = math.clamp(snapshot.progress, 0, 1)

	return e(React.Fragment, nil, {
		LoaderScreen = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0, 0),
			BackgroundColor3 = BACKGROUND_COLOR,
			BorderSizePixel = 0,
			ZIndex = 1000,
		}, {
			Center = e("Frame", {
				Size = UDim2.new(0.56, 0, 0, 76),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 1001,
			}, {
				SizeConstraint = e("UISizeConstraint", {
					MinSize = Vector2.new(288, 76),
					MaxSize = Vector2.new(430, 76),
				}),
				LoadingText = e("TextLabel", {
					Size = UDim2.new(1, 0, 0, 22),
					Position = UDim2.fromOffset(0, 0),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = LOADER_FONT,
					Text = resolveLoadingText(snapshot),
					TextColor3 = TEXT_COLOR,
					TextSize = 16,
					TextTransparency = 0,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					ZIndex = 1002,
				}),
				BarTrack = e("Frame", {
					Size = UDim2.new(1, 0, 0, 8),
					Position = UDim2.fromOffset(0, 34),
					BackgroundColor3 = TRACK_COLOR,
					BorderSizePixel = 0,
					ClipsDescendants = true,
					ZIndex = 1002,
				}, {
					BarFill = e("Frame", {
						Size = UDim2.fromScale(progress, 1),
						Position = UDim2.fromScale(0, 0),
						BackgroundColor3 = BAR_COLOR,
						BorderSizePixel = 0,
						ZIndex = 1003,
					}),
				}),
				Percentage = e("TextLabel", {
					Size = UDim2.new(1, 0, 0, 20),
					Position = UDim2.fromOffset(0, 48),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = LOADER_FONT,
					Text = formatPercent(progress),
					TextColor3 = TEXT_COLOR,
					TextSize = 16,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					ZIndex = 1002,
				}),
			}),
		}),
	})
end

return LoaderGui
