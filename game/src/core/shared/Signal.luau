--!strict
-- 최소 Signal 구현 (Connect / Once / Fire / DisconnectAll)

export type Connection = { Disconnect: (self: Connection) -> (), Connected: boolean }
export type Signal = {
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Once: (self: Signal, fn: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
	local self = setmetatable({ _handlers = {} :: { any } }, Signal)
	return (self :: any) :: Signal
end

function Signal:Connect(fn)
	local conn = { Connected = true, _fn = fn }
	local handlers = self._handlers
	table.insert(handlers, conn)
	function conn.Disconnect(c)
		if not c.Connected then
			return
		end
		c.Connected = false
		local i = table.find(handlers, c)
		if i then
			table.remove(handlers, i)
		end
	end
	return conn
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...)
	local snapshot: { any } = table.clone(self._handlers)
	-- 한 리스너 오류가 뒤 리스너(예: 나갈 때 Factory.stop → 저장)를 막지 않게 (2026-10-20 리뷰)
	for _, conn in snapshot do
		if conn.Connected then
			local ok, err = pcall(conn._fn, ...)
			if not ok then
				warn("[Signal] handler error:", err)
			end
		end
	end
end

function Signal:DisconnectAll()
	for _, conn in self._handlers do
		conn.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
