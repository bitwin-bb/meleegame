-- Opt-in only, so the runtime startup folder does not execute tests during normal play.
if script:GetAttribute("RunTests") == true then
	local RunService = game:GetService("RunService")
	local ServerScriptService = game:GetService("ServerScriptService")

	local PACKAGE_NAME = "AquariaBackup"
	local PACKAGE_LOAD_TIMEOUT_SECONDS = 10
	local PROJECT_LOADER_LINK_NAME = "loader"
	local NEVERMORE_LOADER_LINK_NAME = "loader"

	local function getPackageRoot(): Instance
		local deadline = os.clock() + PACKAGE_LOAD_TIMEOUT_SECONDS

		while os.clock() < deadline do
			local packageRoot = ServerScriptService:FindFirstChild(PACKAGE_NAME)
			if packageRoot ~= nil then
				return packageRoot
			end
			task.wait(0.05)
		end

		error(`[runTests] Missing {PACKAGE_NAME}.`)
	end

	local packageRoot = getPackageRoot()

	local gameRoot = packageRoot:FindFirstChild("game")
		or packageRoot:WaitForChild("game", PACKAGE_LOAD_TIMEOUT_SECONDS)
	assert(gameRoot ~= nil, `[runTests] Missing game folder in {packageRoot:GetFullName()}.`)
	packageRoot:WaitForChild("node_modules", PACKAGE_LOAD_TIMEOUT_SECONDS)
	local serverRoot = gameRoot:FindFirstChild("Server")
		or gameRoot:WaitForChild("Server", PACKAGE_LOAD_TIMEOUT_SECONDS)
	assert(serverRoot ~= nil, `[runTests] Missing game.Server folder in {packageRoot:GetFullName()}.`)
	local serverSourceRoot = serverRoot:FindFirstChild("Source")
		or serverRoot:WaitForChild("Source", PACKAGE_LOAD_TIMEOUT_SECONDS)
	assert(serverSourceRoot ~= nil, `[runTests] Missing game.Server.Source folder in {packageRoot:GetFullName()}.`)

	local loader = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils").Parent
	assert(loader ~= nil and loader:IsA("ModuleScript"), "[runTests] Missing loader module.")

	local function disableStudioWallyIndexPackageTrackerModules(root: Instance)
		if not RunService:IsStudio() then
			return
		end

		local nodeModules = root:FindFirstChild("node_modules")
		if nodeModules == nil then
			return
		end

		local wallyIndex = nodeModules:FindFirstChild("_Index")
		if wallyIndex == nil then
			return
		end

		for _, descendant in wallyIndex:GetDescendants() do
			if descendant:IsA("ModuleScript") then
				descendant.Archivable = false
			end
		end
	end

	disableStudioWallyIndexPackageTrackerModules(packageRoot)
	local require = require(loader).bootstrapGame(packageRoot)

	local loaderLinkUtils = require(loader.LoaderLink.LoaderLinkUtils)
	local function shouldAddProjectloaderLink(container: Instance): boolean
		if container:FindFirstChild(PROJECT_LOADER_LINK_NAME) ~= nil then
			return false
		end

		for _, child in container:GetChildren() do
			if
				child:IsA("ModuleScript")
				and child.Name ~= PROJECT_LOADER_LINK_NAME
				and child.Name ~= NEVERMORE_LOADER_LINK_NAME
			then
				return true
			end
		end

		return false
	end

	local function ensureContainerLink(container: Instance)
		if not shouldAddProjectloaderLink(container) then
			return
		end

		local link = loaderLinkUtils.create(loader, PROJECT_LOADER_LINK_NAME)
		link.Parent = container
	end

	local function ensureProjectloaderLinks(root: Instance)
		if root:IsA("Folder") then
			ensureContainerLink(root)
		end

		for _, descendant in root:GetDescendants() do
			if descendant:IsA("Folder") or descendant:IsA("ModuleScript") then
				ensureContainerLink(descendant)
			end
		end
	end

	ensureProjectloaderLinks(gameRoot)

	local TestEZ = require("TestEZ")
	local serverTests = serverSourceRoot:WaitForChild("Tests", PACKAGE_LOAD_TIMEOUT_SECONDS)

	local testBootstrap = TestEZ.TestBootstrap :: any
	testBootstrap.run(testBootstrap, {
		serverTests:WaitForChild("Specs"),
	})
end
