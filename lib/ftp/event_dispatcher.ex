defmodule Ftp.EventDispatcher do
  @server_name __MODULE__
  require Logger

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(_args \\ []) do
    Registry.start_link(:duplicate, @server_name)
  end

  def register(item, meta \\ nil)

  def register(item, meta) when is_binary(item) do
    item
    |> String.to_atom()
    |> register(meta)
  end

  def register(item, meta) when is_atom(item) do
    Logger.info("Successfully registerd #{item}")
    Registry.register(@server_name, item, meta)
  end

  def unregister(item) when is_binary(item) do
    item
    |> String.to_atom()
    |> register()
  end

  def unregister(item) when is_atom(item) do
    Registry.unregister(@server_name, item)
  end

  defp log_dispatch(event) do
    Logger.debug(fn ->
      "#{__MODULE__}: Dispatching event '#{event}'
        }"
    end)
  end

  def dispatch(event) when is_atom(event) do
    log_dispatch(event)

    Registry.dispatch(@server_name, event, fn entries ->
      for {pid, meta} <- entries do
        Logger.debug(fn -> "=> #{inspect(pid)} #{inspect(meta)}" end)
        send(pid, {:ftp_event, event})
      end
    end)
  end

  def dispatch(event) do
    Logger.error("Not dispatching event #{inspect(event)}. Event must be in Atom format.")
  end
end
