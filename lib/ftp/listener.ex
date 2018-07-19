defmodule Ftp.Listener do
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    Ftp.EventDispatcher.register(:event1)
    Ftp.EventDispatcher.register(:event2)
    {:ok, %{}}
  end

  def handle_info({:ftp_event, event}, state) do
    Logger.info("#{__MODULE__} Got an event: #{inspect(event)}")
    {:noreply, state}
  end
end
