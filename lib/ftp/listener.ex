defmodule Ftp.Listener do
    @moduledoc """
    Module for testing event dispatcher.
    TODO --> delete when testing is complete.
    """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    Application.get_env(:ftp, :events)
      |> Enum.each(fn(event) -> Ftp.EventDispatcher.register(event) end)

    {:ok, %{}}
  end

  def handle_info({:ftp_event, event}, state) do
    Logger.info("#{__MODULE__} Got an event: #{inspect(event)}")
    {:noreply, state}
  end
end
