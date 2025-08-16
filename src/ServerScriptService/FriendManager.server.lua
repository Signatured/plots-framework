--!strict

local Players = game:GetService("Players")

local ServerScriptService = game:GetService("ServerScriptService")
local ServerPlot = require(ServerScriptService.Plot.ServerPlot)

local function applyFriendBoostFor(player: Player)
	local plot = ServerPlot.GetByPlayer(player)
	if not plot then
		return
	end

	local friendsInServer = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local ok, isFriend = pcall(function()
				return player:IsFriendsWith(other.UserId)
			end)
			if ok and isFriend then
				friendsInServer += 1
			end
		end
	end

	local boost = friendsInServer * 10
	plot:SessionSet("FriendBoost", boost)
end

local function applyAll()
	for _, player in ipairs(Players:GetPlayers()) do
		applyFriendBoostFor(player)
	end
end

-- Update every second
task.spawn(function()
	while true do
		applyAll()
		task.wait(1)
	end
end)

-- Also update on player list changes for responsiveness
Players.PlayerAdded:Connect(function()
	applyAll()
end)

Players.PlayerRemoving:Connect(function(removing: Player)
	-- Ensure others' boosts are recalculated when someone leaves
	applyAll()
end)


