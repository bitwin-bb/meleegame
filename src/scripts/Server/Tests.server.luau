--!strict

-- Opt-in only, so the runtime startup folder does not execute tests during normal play.
if script:GetAttribute("RunTests") == true then
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local PACKAGE_NAME = "AquariaBackup"
	local PACKAGE_LOAD_TIMEOUT_SECONDS = 10

	local function resolvePackageRoot(): Instance
		local deadline = os.clock() + PACKAGE_LOAD_TIMEOUT_SECONDS

		while os.clock() < deadline do
			local packageRoot = ReplicatedStorage:FindFirstChild(PACKAGE_NAME)
				or ServerScriptService:FindFirstChild(PACKAGE_NAME)
			if packageRoot ~= nil then
				return packageRoot
			end
			task.wait(0.05)
		end

		error(`[runTests] Missing {PACKAGE_NAME}.`)
	end

	local packageRoot = resolvePackageRoot()

	local gameRoot = packageRoot:FindFirstChild("game")
		or packageRoot:WaitForChild("game", PACKAGE_LOAD_TIMEOUT_SECONDS)
	assert(gameRoot ~= nil, `[runTests] Missing game folder in {packageRoot:GetFullName()}.`)
	local serverRoot = gameRoot:FindFirstChild("Server")
		or gameRoot:WaitForChild("Server", PACKAGE_LOAD_TIMEOUT_SECONDS)
	assert(serverRoot ~= nil, `[runTests] Missing game.Server folder in {packageRoot:GetFullName()}.`)

	local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
	;(require :: any)(loaderUtils.Parent).bootstrapGame(packageRoot)

	local TestEZ = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Vendor"):WaitForChild("TestEZ"))
	local serverTests = serverRoot:WaitForChild("Tests", PACKAGE_LOAD_TIMEOUT_SECONDS)

	local testBootstrap = TestEZ.TestBootstrap :: any
	testBootstrap.run(testBootstrap, {
		serverTests:WaitForChild("Specs"),
	})
end
