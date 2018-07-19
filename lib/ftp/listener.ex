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
    for event <- Application.get_env(:ftp, :events), do: Ftp.EventDispatcher.register(event)
    {:ok, %{}}
  end

  def handle_info({:ftp_event, event}, state) do
    Logger.info("#{__MODULE__} Got an event: #{inspect(event)}")
    {:noreply, state}
  end
end
