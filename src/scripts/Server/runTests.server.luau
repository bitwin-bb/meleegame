--!strict

-- Opt-in only, so the runtime startup folder does not execute tests during normal play.
if script:GetAttribute("RunTests") == true then
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local PACKAGE_NAME = "AquariaBackup"
	local PACKAGE_LOAD_TIMEOUT_SECONDS = 10

	local packageRoot = ServerScriptService:FindFirstChild(PACKAGE_NAME)
		or ServerScriptService:WaitForChild(PACKAGE_NAME, PACKAGE_LOAD_TIMEOUT_SECONDS)
	assert(packageRoot ~= nil, `[runTests] Missing ServerScriptService.{PACKAGE_NAME}.`)

	local gameRoot = packageRoot:FindFirstChild("game") or packageRoot:WaitForChild("game", PACKAGE_LOAD_TIMEOUT_SECONDS)
	assert(gameRoot ~= nil, `[runTests] Missing game folder in {packageRoot:GetFullName()}.`)
	local serverRoot = gameRoot:FindFirstChild("Server") or gameRoot:WaitForChild("Server", PACKAGE_LOAD_TIMEOUT_SECONDS)
	assert(
		serverRoot ~= nil,
		`[runTests] Missing game.Server folder in {packageRoot:GetFullName()}.`
	)

	local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
	require(loaderUtils.Parent).bootstrapGame(packageRoot)

	local TestEZ = require(ReplicatedStorage.Packages.TestEZ)
	local serverTests = serverRoot:WaitForChild("Tests", PACKAGE_LOAD_TIMEOUT_SECONDS)

	TestEZ.TestBootstrap:run({
		serverTests:WaitForChild("Specs"),
	})
end
