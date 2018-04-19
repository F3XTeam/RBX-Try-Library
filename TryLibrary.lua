-- An asynchronous pcall-wrapper for interdependent error-prone functions
-- @author Validark
-- @readme https://github.com/F3XTeam/RBX-Try-Library/blob/master/README.md

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Resources = require(ReplicatedStorage:WaitForChild("Resources"))
local Enumeration = Resources:LoadLibrary("Enumeration")

Enumeration.AttemptType = {"Try", "Then", "Catch", "Retry"}

local function Continue(self, Position, HistoryCount, Success, Error, ...)
	local History = self.History
	if HistoryCount == #History then
		if Success then
			for Position = Position + 3, self.Count, 3 do
				if self[Position] == Enumeration.AttemptType.Then or self[Position] == Enumeration.AttemptType.Try then -- Enter next `Then` or `Try` function
					self.LastArguments = {Error, ...}
					History[HistoryCount + 1] = Position -- Log that we pcalled this statement
					return Continue(self, Position, HistoryCount + 1, pcall(self[Position + 1], Error, ...)) -- Call next Then with arguments
				end
			end
		else
			for Position = Position + 3, self.Count, 3 do
				if self[Position] == Enumeration.AttemptType.Catch then -- Enter next `Catch` function
					-- Get arguments and predicate count
					local Arguments = self[Position + 1]
					local PredicateCount = #Arguments - 1
					local Caught = PredicateCount == 0

					-- Handle matching error if strings were passed into Catch
					if not Caught and type(Error) == "string" then
						for Predicate = 1, PredicateCount do
							if Error:match(Arguments[Predicate]) then
								Caught = true
								break
							end
						end
					end

					if Caught then
						HistoryCount = HistoryCount + 1
						History[HistoryCount] = Position -- Log that we pcalled this statement

						-- Assemble Traceback
						local Traceback = "Stack Begin\n"
						for a = 1, HistoryCount do
							local Position = History[a]
							local Type = self[Position]

							local Message = (
								Type == Enumeration.AttemptType.Try and self[Position + 2]:match("Try.-[\n\r]([^\n\r]+)") .. " - upvalue Try\n" or
								Type == Enumeration.AttemptType.Then and self[Position + 2]:match("%- method Then[\n\r]([^\n\r]+)") .. " - method Then\n" or
								Type == Enumeration.AttemptType.Catch and self[Position + 2]:match("%- method Catch[\n\r]([^\n\r]+)") .. " - method Catch\n" or
								Type == Enumeration.AttemptType.Retry and self[Position + 2]:match("%- method Retry[\n\r]([^\n\r]+)") .. " - method Retry\n"
							)

							if Message then
								Traceback = Traceback .. Message
							end
						end

						return Continue(self, Position, HistoryCount, pcall(Arguments[PredicateCount + 1], Error, Traceback .. "Stack End", self))
					end
				end
			end
		end

		-- This is what we are reduced to because Roblox refuses to fix coroutine.yield
		-- https://devforum.roblox.com/t/wait-breaks-coroutine-yield/52881
		self.Data = {Position, HistoryCount, Success, Error, ...}

		-- Don't resolve thread if `Retry` was initiated
		if self.PreviousRetryCount == self.RetryCount then
			self.Resolved, self.RetryCount = true
		else
			self.PreviousRetryCount = self.RetryCount
		end
	end
end

local Attempt = {
	__index = {
		[0] = Enumeration.AttemptType.Try;
		Count = 2;
		RetryCount = 0;
		PreviousRetryCount = 0;
	}
}

function Attempt:__tostring()
	if not self.Id then
		self.Id = tostring{}:gsub("table", "attempt")
	end
	return self.Id
end

function Attempt.__index:Then(Function)
	local Count = self.Count
	self.Count = Count + 3

	self[Count + 1] = Enumeration.AttemptType.Then
	self[Count + 2] = Function
	self[Count + 3] = debug.traceback()

	if self.Resolved then
		self.Resolved = false
		coroutine.resume(coroutine.create(Continue), self, unpack(self.Data))
	end

	return self
end

function Attempt.__index:Catch(...)
	local Count = self.Count
	self.Count = Count + 3

	self[Count + 1] = Enumeration.AttemptType.Catch
	self[Count + 2] = {...}
	self[Count + 3] = debug.traceback()

	if self.Resolved then
		self.Resolved = false
		coroutine.resume(coroutine.create(Continue), self, unpack(self.Data))
	end

	return self
end

function Attempt.__index:Wait()
	while not self.Resolved do wait() end
	return self
end

function Attempt.__index:Retry()
	self.RetryCount = self.RetryCount + 1

	local History = self.History
	local HistoryCount = #History

	local Count = self.Count
	self.Count = Count + 3

	self[Count + 1] = Enumeration.AttemptType.Retry
	self[Count + 2] = true -- Place where we encountered an error: History[HistoryCount - 1]
	self[Count + 3] = debug.traceback()

	for a = HistoryCount - 1, 1, -1 do -- We subtract 1 from HistoryCount so as to not include the current statement
		local ErrorPosition = History[a]
		local Identity = self[ErrorPosition]
		if Identity ~= Enumeration.AttemptType.Retry then -- Find the last non-retry statement and start it up
			History[HistoryCount + 1] = Count + 1 -- Log Enumeration.AttemptType.Retry Position Above ^^
			coroutine.resume(coroutine.create(Continue), self, ErrorPosition - 3, HistoryCount + 1, Identity ~= Enumeration.AttemptType.Catch, unpack(self.LastArguments))
			return self
		end
	end

	error("[Try] Attempt has nothing to `Retry`")
end

local function Try(Function, ...)
	--- Calls Function with (...) in protected mode, and returns chainable Attempt
	-- @returns Attempt Object

	local self = setmetatable({
		Function, debug.traceback();
		History = {};
	}, Attempt)

	coroutine.resume(coroutine.create(Continue), self, -3, 0, true, ...) -- We subtract 3 because it will be added back in Continue

	return self
end

return Try
