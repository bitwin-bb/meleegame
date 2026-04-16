--!strict

-- Opt-in only, so the runtime startup folder does not execute tests during normal play.
if script:GetAttribute("RunTests") == true then
	local ServerScriptService = game:GetService("ServerScriptService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local PACKAGE_NAME = "AquariaBackup"

	local packageRoot = ServerScriptService:FindFirstChild(PACKAGE_NAME)
	assert(packageRoot ~= nil, `[runTests] Missing ServerScriptService.{PACKAGE_NAME}.`)

	local gameRoot = packageRoot:FindFirstChild("game")
	assert(gameRoot ~= nil, `[runTests] Missing game folder in {packageRoot:GetFullName()}.`)
	assert(
		gameRoot:FindFirstChild("Server") ~= nil,
		`[runTests] Missing game.Server folder in {packageRoot:GetFullName()}.`
	)

	local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
	require(loaderUtils.Parent).bootstrapGame(packageRoot)

	local TestEZ = require(ReplicatedStorage.Packages.TestEZ)
	local serverTests = packageRoot:WaitForChild("game"):WaitForChild("Server"):WaitForChild("Tests")

	TestEZ.TestBootstrap:run({
		serverTests:WaitForChild("Specs"),
	})
end
