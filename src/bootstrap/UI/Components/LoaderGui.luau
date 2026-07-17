--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PACKAGES_NAME = "Packages"
local REACT_NAME = "React"
local PACKAGE_WAIT_TIMEOUT_SECONDS = 60

local FONT = Enum.Font.Code
local BACKGROUND_COLOR = Color3.fromRGB(0, 0, 0)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local TRACK_COLOR = Color3.fromRGB(20, 20, 20)
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

local React = (require :: any)(waitForPackageModule(REACT_NAME))
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

local function coerceNumber(value: any, fallback: number, minimum: number?, maximum: number?): number
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

local function coerceString(value: any, fallback: string): string
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

local function coerceStringArray(valueRaw: any): { string }
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

local function coerceSnapshot(valueRaw: any): LoaderSnapshot
	local value: { [string]: any } = if typeof(valueRaw) == "table" then valueRaw :: { [string]: any } else {} :: any

	return {
		status = coerceString(value.status, DEFAULT_SNAPSHOT.status),
		stage = coerceString(value.stage, DEFAULT_SNAPSHOT.stage),
		message = coerceString(value.message, DEFAULT_SNAPSHOT.message),
		progress = coerceNumber(value.progress, DEFAULT_SNAPSHOT.progress, 0, 1),
		completed = coerceNumber(value.completed, DEFAULT_SNAPSHOT.completed, 0, nil),
		total = coerceNumber(value.total, DEFAULT_SNAPSHOT.total, 1, nil),
		startedAt = coerceNumber(value.startedAt, DEFAULT_SNAPSHOT.startedAt, 0, nil),
		finishedAt = if typeof(value.finishedAt) == "number" then value.finishedAt else nil,
		moduleCount = coerceNumber(value.moduleCount, DEFAULT_SNAPSHOT.moduleCount, 0, nil),
		assetCount = coerceNumber(value.assetCount, DEFAULT_SNAPSHOT.assetCount, 0, nil),
		assetLoadedCount = coerceNumber(value.assetLoadedCount, DEFAULT_SNAPSHOT.assetLoadedCount, 0, nil),
		assetFailedCount = coerceNumber(value.assetFailedCount, DEFAULT_SNAPSHOT.assetFailedCount, 0, nil),
		failureCount = coerceNumber(value.failureCount, DEFAULT_SNAPSHOT.failureCount, 0, nil),
		lastError = if typeof(value.lastError) == "string" and value.lastError ~= "" then value.lastError else nil,
		failures = coerceStringArray(value.failures),
	}
end

local function getLoadingText(snapshot: LoaderSnapshot): string
	if snapshot.status == "failed" then
		return "loader failed"
	end

	local stageText = LOADING_TEXT_BY_STAGE[snapshot.stage]
	if stageText ~= nil then
		return stageText
	end

	return coerceString(snapshot.message, "loading world")
end

local function formatPercent(progress: number): string
	return `{math.floor(math.clamp(progress, 0, 1) * 100 + 0.5)}%`
end

local function LoaderGui(props: LoaderGuiProps): any
	local snapshot = coerceSnapshot(props.snapshot)
	local progress = math.clamp(snapshot.progress, 0, 1)

	return e(React.Fragment, nil, {
		e("Frame", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0, 0),
			BackgroundColor3 = BACKGROUND_COLOR,
			BorderSizePixel = 0,
			ZIndex = 1000,
		}, {
			e("Frame", {
				Size = UDim2.new(0.56, 0, 0, 76),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 1001,
			}, {
				e("UISizeConstraint", {
					MinSize = Vector2.new(288, 76),
					MaxSize = Vector2.new(430, 76),
				}),
				e("TextLabel", {
					Size = UDim2.new(1, 0, 0, 22),
					Position = UDim2.fromOffset(0, 0),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = FONT,
					Text = getLoadingText(snapshot),
					TextColor3 = TEXT_COLOR,
					TextSize = 16,
					TextTransparency = 0,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextYAlignment = Enum.TextYAlignment.Center,
					ZIndex = 1002,
				}),
				e("Frame", {
					Size = UDim2.new(1, 0, 0, 4),
					Position = UDim2.fromOffset(0, 34),
					BackgroundColor3 = TRACK_COLOR,
					BorderSizePixel = 0,
					ClipsDescendants = true,
					ZIndex = 1002,
				}, {
					e("Frame", {
						Size = UDim2.fromScale(progress, 1),
						Position = UDim2.fromScale(0, 0),
						BackgroundColor3 = BAR_COLOR,
						BorderSizePixel = 0,
						ZIndex = 1003,
					}),
				}),
				e("TextLabel", {
					Size = UDim2.new(1, 0, 0, 20),
					Position = UDim2.fromOffset(0, 48),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Font = FONT,
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
