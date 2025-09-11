--!strict

local Players = game:GetService("Players")
local ClientPlot = require(game.ReplicatedStorage.Plot.ClientPlot)
local Functions = require(game.ReplicatedStorage.Library.Functions)

local localPlayer = Players.LocalPlayer

ClientPlot.OnLocalAndCreated(function(plot: ClientPlot.Type)
    local spawn = plot:WaitSpawnCFrame()
    local teleportCFrame = spawn + Vector3.new(0, 3, 0) 

    Functions.PivotPlayer(localPlayer, teleportCFrame)

    localPlayer.CharacterAdded:Connect(function()
        Functions.PivotPlayer(localPlayer, teleportCFrame)
    end)
end)

ClientPlot.OnAllAndCreated(function(plot: ClientPlot.Type)
    if plot:IsLocal() then
        return
    end

    local model = plot:YieldModel()
    if model then
        local advertSign = model:FindFirstChild("AdvertSign")::BasePart

        if advertSign then
            advertSign:Destroy()
        end
    end
end)