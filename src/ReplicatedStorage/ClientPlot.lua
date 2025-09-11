--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Event = require(ReplicatedStorage.Library.Modules.Event)
local Network = require(ReplicatedStorage.Library.Client.Network)
local Functions = require(ReplicatedStorage.Library.Functions)
local Directory = require(ReplicatedStorage.Game.Library.Directory)
local SharedGameSettings = require(ReplicatedStorage.Game.Library.GameSettings)
local Save = require(ReplicatedStorage.Library.Client.Save)

local PlotTypes = require(ReplicatedStorage.Game.Library.Types.Plots)

type Fields<self> = {
    Id: number,
    Owner: Player,
    CFrame: CFrame,
    ModelName: string,
    Destroyed: boolean,
    Created: number,

    NetworkHandlers: {[string]: (self, ...any) -> (...any)},

    SaveVariables: {[string]: any},
    SaveVariableChanged: {[string]: Event.EventInstance},
    SessionVariables: {[string]: any},
    SessionVariableChanged: {[string]: Event.EventInstance},
    LocalVariables: {[any]: any},

    ModelAdded: Event.EventInstance,
    Destroying: Event.EventInstance,
    Heartbeat: Event.EventInstance,
    RenderStepped: Event.EventInstance,
}

type Functions<self> = {
    GetId: (self) -> number,
    GetOwner: (self) -> Player,
    GetCFrame: (self) -> CFrame,
    GetModel: (self) -> Model?,
    YieldModel: (self) -> Model,
    IsLocal: (self) -> boolean,

    GetSpawnCFrame: (self) -> CFrame,
    WaitSpawnCFrame: (self) -> CFrame,
    GetFish: (self, index: number) -> PlotTypes.Fish?,
    GetAllFish: (self) -> {[string]: PlotTypes.Fish},
    GetFishLevel: (self, index: number) -> number?,
    GetFishEarnings: (self, index: number) -> number,
    GetFishOfflineEarnings: (self, index: number) -> number,
    GetMoneyPerSecond: (self, index: number) -> number?,
    GetUpgradeCost: (self, index: number) -> number?,
    GetSellPrice: (self, index: number) -> number?,
    CanAfford: (self, cost: number) -> boolean,
    GetMultiplier: (self) -> number,

    ModelCreated: (self, callback: (Model) -> ()) -> (),

    RunHeartbeat: (self, dt: number) -> (),
    RunRenderStepped: (self, dt: number) -> (),
    IsDestroyed: (self) -> boolean,
    Destroy: (self) -> boolean,

    Fired: (self, type: string, handler: (self, ...any) -> (...any)) -> (),
    Invoke: (self, name: string, ...any) -> (...any),
    Fire: (self, type: string, ...any) -> (),

    Save: (self, key: string) -> any,
	SaveUpdated: (self, key: string) -> Event.EventInstance,
	Session: (self, key: string) -> any,
	SessionUpdated: (self, key: string) -> Event.EventInstance,
	Local: (self, key: any) -> any,
	LocalSet:(self, key: any, val: any) -> (),
}

export type Type = Fields<Type> & Functions<Type>

local prototype = {}::(Functions<Type>)

local Plots: {[number]: Type} = {}
local PlotsByPlayer: {[Player]: Type} = {}

local Created = Event.new()
local Destroying = Event.new()

function prototype:GetId(): number
    return self.Id
end

function prototype:GetOwner(): Player
    return self.Owner
end

function prototype:GetCFrame(): CFrame
    return self.CFrame
end

function prototype:GetModel(): Model?
    local thingsFolder = workspace:FindFirstChild("__THINGS")
    if not thingsFolder then
        return nil
    end
    local plotsFolder = thingsFolder:FindFirstChild("Plots")
    if not plotsFolder then
        return nil
    end
    local model = plotsFolder:FindFirstChild(self.ModelName)
    if not model then
        return nil
    end
    return model
end

function prototype:YieldModel(): Model
    while not self:GetModel() do
        if self:IsDestroyed() then
            error("Plot destroyed while waiting for model")
        end
        task.wait()
    end
    local model = self:GetModel()
    assert(model, "Model not found")
    return model
end

function prototype:ModelCreated(callback: (Model) -> ())
    self.ModelAdded:Connect(callback)
    local model = self:GetModel()
    if model then
        callback(model)
    end
end

function prototype:GetSpawnCFrame(): CFrame
    local model = self:YieldModel()
    local spawnPart = model:FindFirstChild("Spawn")::BasePart
    return spawnPart:GetPivot()
end

function prototype:WaitSpawnCFrame(): CFrame
    while not self:GetSpawnCFrame() do
        if self:IsDestroyed() then
            error("Plot destroyed while waiting for CFrame")
        end
        task.wait()
    end
    local spawnCFrame = self:GetSpawnCFrame()
    assert(spawnCFrame, "CFrame not found")
    return spawnCFrame
end

function prototype:IsLocal(): boolean
    return self.Owner == Players.LocalPlayer
end

function prototype:IsDestroyed()
    return self.Destroyed
end

function prototype:Destroy(): boolean
	if self.Destroyed then
		return false
	end
	self.Destroyed = true

	-- Notify first so listeners can clean up while model/registries still exist
	self.Destroying:FireAsync()
	Destroying:FireAsync(self)

	-- Unindex
	if Plots[self.Id] == self then
		Plots[self.Id] = nil
	end
	if self.Owner and PlotsByPlayer[self.Owner] == self then
		PlotsByPlayer[self.Owner] = nil
	end

	-- Model teardown
	local model = self:GetModel()
	if model then
		model:Destroy()
	end

	-- Disconnect per-instance events
	self.ModelAdded:Disconnect()
	self.Destroying:Disconnect()
	self.Heartbeat:Disconnect()
	self.RenderStepped:Disconnect()

	return true
end

function prototype:Fired(type: string, handler: (...any) -> (...any))
    if self.NetworkHandlers[type] then
        error(`Handler for type '{type}' already exists`)
    end
    
    self.NetworkHandlers[type] = handler
end

function prototype:Invoke(name: string, ...)
    return Network.Invoke("Plots_Invoke", self.Id, name, ...)
end

function prototype:Fire(type: string, ...)
    Network.Fire("Plots_Fire", self.Id, type, ...)
end

function prototype:RunHeartbeat(dt: number)
    self.Heartbeat:FireAsync(dt)
end

function prototype:RunRenderStepped(dt: number)
    self.RenderStepped:FireAsync(dt)
end

function prototype:GetFish(index: number): PlotTypes.Fish?
    local fishes = self:GetAllFish()
    return fishes[tostring(index)]
end

function prototype:GetAllFish(): {[string]: PlotTypes.Fish}
    local fishes = self:Save("Fish")
    if not fishes then
        return {}
    end
    return fishes
end

function prototype:GetFishLevel(index: number): number?
    local fish = self:GetFish(index)
    if not fish then
        return nil
    end
    return fish.FishData.Level
end

function prototype:GetFishEarnings(index: number): number
    local fish = self:GetFish(index)
    if not fish then
        return 0
    end
    -- Earnings are now accumulated on the server and replicated via Save updates
    local earnings = fish.Earnings or 0
    return math.floor(earnings)
end

function prototype:GetFishOfflineEarnings(index: number): number
    local fish = self:GetFish(index)
    if not fish then
        return 0
    end
    return math.floor(fish.OfflineEarnings or 0)
end

function prototype:GetMoneyPerSecond(index: number): number?
	local fish = self:GetFish(index)
	if not fish then
		return nil
	end
    local dir = Directory.Fish[fish.FishId]
    return dir.MoneyPerSecond * fish.FishData.Level
end

function prototype:GetUpgradeCost(index: number): number?
	local fish = self:GetFish(index)
	if not fish then
		return nil
	end
    local fishLevel = self:GetFishLevel(index)
	if not fishLevel then
		return nil
	end
	local nextLevel = fishLevel + 1
	if nextLevel > SharedGameSettings.MaxLevel then
		return nil
	end

    local dir = Directory.Fish[fish.FishId]
	return dir.BaseUpgradeCost * (1.5 ^ (nextLevel - 1))
end

function prototype:GetSellPrice(index: number): number?
	local moneyPerSecond = self:GetMoneyPerSecond(index)
	if not moneyPerSecond then
		return nil
	end
    return math.ceil(moneyPerSecond * 20)
end

function prototype:CanAfford(cost: number): boolean
    local money = self:Save("Money")
    if not money then
        return false
    end
    return money >= cost
end

function prototype:GetMultiplier(): number
    local doubleMoneyGamepassId = 1407961498
    local multiplier = 1
	local friendBoost = self:Session("FriendBoost") or 0
	local paidIndex = self:Save("PaidIndex") or 0
	local paidMultiplier = 0.5 * paidIndex
    local questExpireTime = self:Session("DailyQuests_Multiplied")
    local questMultiplier = 0
	if questExpireTime and workspace:GetServerTimeNow() < questExpireTime then
		questMultiplier = 1
	end

    local save = Save.Get()
    local ownsGamepass = save and save.Gamepasses and save.Gamepasses[tostring(doubleMoneyGamepassId)] or false
	if ownsGamepass then
		multiplier = multiplier + 1
	end

	multiplier = multiplier + (Functions.Round(friendBoost / 100, 1) + paidMultiplier + questMultiplier)
	return multiplier
end

function prototype:Save(key: string)
    return self.SaveVariables[key]
end

function prototype:SaveUpdated(key: string): Event.EventInstance
	local result = self.SaveVariableChanged[key]
	if not result then
		result = Event.new()
		self.SaveVariableChanged[key] = result
	end
	return result::any
end

function prototype:Session(key: string)
    return self.SessionVariables[key]
end

function prototype:SessionUpdated(key: string): Event.EventInstance
	local result = self.SessionVariableChanged[key]
	if not result then
		result = Event.new()
		self.SessionVariableChanged[key] = result
	end
	return result::any
end

function prototype:Local(key: any)
    return self.LocalVariables[key]
end

function prototype:LocalSet(key: any, val: any)
    self.LocalVariables[key] = val
end

local Metatable = table.freeze({ __index = table.freeze(prototype) })

local module = {
    Created = Created,
    Destroying = Destroying,
}

local function applySaveUpdates(self: Type, updates: {{any}})
    if not updates then return end
    for _, pair in ipairs(updates) do
        local key = pair[1]
        local val = pair[2]
        local oldVal = self.SaveVariables[key]
        self.SaveVariables[key] = val

        local event = self.SaveVariableChanged[key]
        if event then
            event:FireAsync(val, oldVal)
        end
    end
end

local function applySessionUpdates(self: Type, updates: {{any}})
    if not updates then return end
    for _, pair in ipairs(updates) do
        local key = pair[1]
        local val = pair[2]
        local oldVal = self.SessionVariables[key]
        self.SessionVariables[key] = val

        local event = self.SessionVariableChanged[key]
        if event then
            event:FireAsync(val, oldVal)
        end
    end
end

local function handlePacket(self: Type, packet: PlotTypes.Packet)
    local ptype = packet.PacketType
    if ptype == "Join" then
        local data = packet.Data
        local modelName = tostring(packet.PlotId)
        self.Owner = data.Owner
        self.CFrame = data.CFrame
        self.ModelName = modelName
        self.SaveVariables = data.SaveVariables or {}
        self.SessionVariables = data.SessionVariables or {}
        if self:GetModel() then
            self.ModelAdded:FireAsync(self:GetModel())
        end
    elseif ptype == "Leave" then
        if not self:IsDestroyed() then
            self:Destroy()
        end
    elseif ptype == "Update" then
        local payload = packet.Data or {}
        applySaveUpdates(self, payload.Save)
        applySessionUpdates(self, payload.Session)
    else
        local handler = self.NetworkHandlers[ptype]
        if handler then
            task.spawn(function()
                handler(self, packet.Data)
            end)
        end
    end
end

function module.GetById(id: number): Type
    return Plots[id]
end

function module.GetAll(): {Type}
    local list = {}
    for _, inst in pairs(Plots) do
        table.insert(list, inst)
    end
    return list
end

function module.GetLocal(): Type?
    return PlotsByPlayer[Players.LocalPlayer]
end

function module.OnLocalAndCreated(callback: ((Type) -> ())?): Type?
    local localPlot = module.GetLocal()
    if localPlot then
        if callback then
            task.spawn(callback, localPlot)
        end
        return localPlot
    end

    if callback then
        local conn
        conn = Created:Connect(function(inst: Type)
            if inst and inst:IsLocal() then
                if conn then
                    conn:Disconnect()
                end
                task.spawn(callback, inst)
            end
        end)
    end

    return nil
end

function module.OnAllAndCreated(callback: ((Type) -> ()))
    for _, plot in module.GetAll() do
        task.spawn(callback, plot)
    end

    Created:Connect(function(plot: Type)
        task.spawn(callback, plot)
    end)
end

function module.NewFromServer(packet: PlotTypes.Packet)
    local id = packet.PlotId
    local self: Type = setmetatable({
        Id = id,
        Owner = packet.Data and packet.Data.Owner or nil,
        CFrame = packet.Data and packet.Data.CFrame or CFrame.new(),
        Model = packet.Data and packet.Data.Model or nil,
        Destroyed = false,
        Created = os.clock(),

        NetworkHandlers = {},
        SaveVariables = {},
        SaveVariableChanged = {},
        SessionVariables = {},
        SessionVariableChanged = {},
        LocalVariables = {},

        ModelAdded = Event.new(),
        Destroying = Event.new(),
        Heartbeat = Event.new(),
        RenderStepped = Event.new(),
    }::any, Metatable)
    Plots[id] = self
    if self.Owner then
        PlotsByPlayer[self.Owner] = self
    end
    handlePacket(self, packet)
    Created:FireAsync(self)

    return self
end

function HandlePackets(packets: {PlotTypes.Packet})
    for _, packet in ipairs(packets) do
        local inst = Plots[packet.PlotId]
        if packet.PacketType == "Join" then
            if inst or Plots[packet.PlotId] then
                continue -- already handled
            end

            module.NewFromServer(packet)
            continue
        end

        if inst and not inst:IsDestroyed() then
            handlePacket(inst, packet)
        end
    end
end

Network.Fired("Plots", function(packets: {PlotTypes.Packet})
    HandlePackets(packets)
end)

RunService:BindToRenderStep("Plots", Enum.RenderPriority.Last.Value, function(dt)
    for id, inst in pairs(Plots) do
        if not inst:IsDestroyed() then
            Functions.wcall(inst.RunRenderStepped, inst, dt)
        end
    end
end)

RunService.Heartbeat:Connect(function(dt)
    for id, inst in pairs(Plots) do
        if not inst:IsDestroyed() then
            Functions.wcall(inst.RunHeartbeat, inst, dt)
        end
    end
end)

return module

