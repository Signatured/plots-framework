--!strict

--[[
	Contains shared type definitions for the command system.
]]

export type Parameter = {
	Type: "Player" | "Number" | "String",
	Name: string,
	Optional: boolean?
}

export type Command = {
	Name: string,
	Aliases: {string}?,
	Permissions: {string}?, -- Using group names now
	Parameters: {Parameter}?,
	Execute: (executor: Player, args: {any}) -> ()
}

return {} 