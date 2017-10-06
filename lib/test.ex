defmodule Test do
    

use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    #schedule_work() # Schedule work to be performed on start
    {:ok, state}
  end

  def get do
      GenServer.call __MODULE__, :get
  end

  def handle_call(:get, _from, state=%{}) do
    # Do the desired work here
    IO.puts "This is call: #{inspect _from}" # Reschedule once more
    {:reply, state, state}
  end

  def handle_info(:work, state=%{}) do
    # Do the desired work here
    schedule_work() # Reschedule once more
    {:noreply, state}
  end

  def handle_info(:hello, state=%{}) do
    IO.puts "This is msg: hello"
    {:noreply, state}
end

  defp schedule_work() do
    IO.puts "Hello"
    Process.send_after(self(), :work, 2 * 1000) # In 2 hours
    #Kernel.send(self(),:work)
  end

end