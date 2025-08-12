--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Player = require(ReplicatedStorage.Library.Player)
local Event = require(ReplicatedStorage.Library.Modules.Event)
local FishTypes = require(ReplicatedStorage.Game.GameLibrary.Types.Fish)
local PlotTypes = require(ReplicatedStorage.Game.GameLibrary.Types.Plots)
local Saving = require(ServerScriptService.Library.Saving)
local Network = require(ServerScriptService.Library.Network)
local Functions = require(ReplicatedStorage.Library.Functions)

type Fields<self> = {
	Id: number,
	Owner: Player,
	CFrame: CFrame,
	Model: Model,
	Destroyed: boolean,
	Created: number,

	Joins: {[Player]: boolean},
	OwnerInvokeHandlers: {[string]: (...any) -> (...any)},
	OtherInvokeHandlers: {[string]: (Player, ...any) -> (...any)},
	InvokeHandlers: {[string]: (Player, ...any) -> (...any)},

	SaveVariables: {[string]: any},
	SaveVariableUpdates: {[string]: any},
	SaveVariableChanged: {[string]: Event.EventInstance},
	SessionVariables: {[string]: any},
	SessionVariableUpdates: {[string]: any},
	SessionVariableChanged: {[string]: Event.EventInstance},
	LocalVariables: {[any]: any},

	Destroying: Event.EventInstance,
	Heartbeat: Event.EventInstance,
	FishAdded: Event.EventInstance,
	FishRemoved: Event.EventInstance
}

type Functions<self> = {
	IsDestroyed: (self) -> boolean,
	Destroy: (self) -> boolean,

	GetId: (self) -> number,
	GetOwner: (self) -> Player,
	GetCFrame: (self) -> CFrame,
	GetModel: (self) -> Model,

	CreateFish: (self, fish: FishTypes.data_schema, index: number) -> (),
	GetFish: (self, index: number) -> FishTypes.data_schema,
	DeleteFish: (self, index: number) -> (),
	GetAllFish: (self) -> {FishTypes.data_schema},
	ClaimEarnings: (self, index: number) -> (),
	SellFish: (self, index: number) -> (),
	PickupFish: (self, index: number) -> (),
	GetMoney: (self) -> number,
	AddMoney: (self, amount: number) -> (),

	Join: (self, player: Player) -> boolean,
	Unjoin: (self, player: Player) -> boolean,
	IsJoined: (self, player: Player) -> boolean,
	GetSubscriptions: (self) -> {Player},
	Broadcast: (self, packet: PlotTypes.Packet) -> (),
	OwnerInvoked: (self, name: string, callback: (...any) -> ...any) -> (),
	OtherInvoked: (self, name: string, callback: (Player, ...any) -> ...any) -> (),
	Invoked: (self, name: string, callback: (Player, ...any) -> ...any) -> (),

	Save: <T>(self, key: string) -> T,
	SaveSet: <T>(self, key: string, val: T?) -> T?,
	SaveChanged: <T>(self, key: string) -> Event.EventInstance,
	Session: <T>(self, key: string) -> T,
	SessionSet: <T>(self, key: string, val: T?) -> T?,
	SessionChanged: <T>(self, key: string) -> Event.EventInstance,
	Local: <T>(self, key: any) -> T,
	LocalSet: <T>(self, key: any, val: T?) -> T?
}
export type Type = Fields<Type> & Functions<Type>

local prototype = {}::(Functions<Type>)

function prototype:IsDestroyed()
	return self.Destroyed
end

local Metatable = table.freeze({ __index = table.freeze(prototype) })

local module = {}

local FakeNil = {}

local IdCounter = 0

local GlobalById: {[number]: Type} = {}
local GlobalByPlayer: {[Player]: Type} = {}
local GlobalPlayerPacketQueues: {[Player]: {PlotTypes.Packet}} = {}

local Created = Event.new()

function module.new(owner: Player, blueprint: Model, cFrame: CFrame): Type
	local save = Saving.Get(owner)
	assert(save, "NoSave")
	local plotSave = save.PlotSave

	local id = IdCounter + 1
	IdCounter = id

	local model = blueprint:Clone()
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Name = tostring(id)
	model:PivotTo(cFrame)
	model.Parent = workspace:WaitForChild("__THINGS"):WaitForChild("Plots")

	-- Instance
	local self: Fields<Type> = {
		Id = id,
		Owner = owner,
		CFrame = cFrame,
		Model = model,
		Destroyed = false,
		Created = workspace:GetServerTimeNow(),

		Joins = {},
		OwnerInvokeHandlers = {},
		OtherInvokeHandlers = {},
		InvokeHandlers = {},

		SaveVariables = plotSave.Variables,
		SaveVariableUpdates = {},
		SaveVariableChanged = {},
		SessionVariables = {},
		SessionVariableUpdates = {},
		SessionVariableChanged = {},
		LocalVariables = {},

		Destroying = Event.new(),
		Heartbeat = Event.new(),
		FishAdded = Event.new(),
		FishRemoved = Event.new()
	}
	
	local self: Type = setmetatable(self::any, Metatable)

	GlobalById[id] = self
	GlobalByPlayer[owner] = self
	
	Created:FireAsync(self)

	for _, player in ipairs(game.Players:GetPlayers()) do 
		self:Join(player)
	end
	
	return self
end

function SendPacket(player: Player, packet: PlotTypes.Packet)
	assert(typeof(player) == "Instance" and player:IsA("Player"))
	if not player.Parent then
		return
	end
	local q = GlobalPlayerPacketQueues[player]
	if not q then
		q = {}
		GlobalPlayerPacketQueues[player] = q
	end
	table.insert(q, packet)
end

function DispatchPackets()
	for player, q in pairs(GlobalPlayerPacketQueues) do
		if not player.Parent then
			GlobalPlayerPacketQueues[player] = nil
			continue
		end
		if next(q) then
			Network.Fire(player, "Plots", q)
			table.clear(q)
		end
	end
end

function ComputeUpdate(
	currents: {[string]: any},
	originals: {[string]: any}
): {{any}}
	local results = {}
	for key, prevVal in pairs(originals) do
		local prevVal = if prevVal ~= FakeNil then prevVal else nil
		local val = currents[key]
		if not Functions.DeepEquals(prevVal, val) then
			table.insert(results, {key,val})
		end
	end
	table.clear(originals)
	return results
end

function module.GetByPlayer(player: Player)
	return GlobalByPlayer[player]
end

function module.GetById(id: number)
	return GlobalById[id]
end

function module.GetAll()
	return Functions.Values(GlobalById)
end

RunService.Heartbeat:Connect(function(deltaTime)
	-- Heartbeat
	for id, inst in pairs(GlobalById) do
		if not inst:IsDestroyed() then
			pcall(function()
				inst.Heartbeat:FireAsync(deltaTime)
			end)
		end
		if inst:IsDestroyed() then
			GlobalById[id] = nil
		end
	end
	-- Packets
	DispatchPackets()
end)

function PlayerRemoving(player: Player)
	local inst = module.GetByPlayer(player)
	if inst then
		inst:Destroy()
	end
	for _, inst in pairs(GlobalByPlayer) do
		inst:Unjoin(player)
	end
	GlobalPlayerPacketQueues[player] = nil
end
Players.PlayerRemoving:Connect(PlayerRemoving)

Saving.SaveAdded:Connect(function(player) 
	for _, inst in pairs(GlobalById) do 
		inst:Join(player)
	end
end)

module.Prototype = prototype

return module