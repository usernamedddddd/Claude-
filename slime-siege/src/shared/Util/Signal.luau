--!strict
-- Minimal synchronous signal (no BindableEvents, no yielding in Fire).

export type Connection = { Disconnect: (Connection) -> () }
export type Signal<T...> = {
	Connect: (Signal<T...>, (T...) -> ()) -> Connection,
	Fire: (Signal<T...>, T...) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local handlers: { (T...) -> () } = {}
	local self = {} :: Signal<T...>

	function self.Connect(_: Signal<T...>, fn: (T...) -> ()): Connection
		table.insert(handlers, fn)
		local connection = {} :: Connection
		function connection.Disconnect(_: Connection)
			local index = table.find(handlers, fn)
			if index then
				table.remove(handlers, index)
			end
		end
		return connection
	end

	function self.Fire(_: Signal<T...>, ...: T...)
		for _, fn in table.clone(handlers) do
			fn(...)
		end
	end

	return self
end

return Signal
