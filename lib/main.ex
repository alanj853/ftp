defmodule Main do
  use Supervisor
  require Logger

  @ftp_server_name :test_server
  @name __MODULE__

  use Application

  def start(_type, _args) do
    start_link()
  end

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: @name)
  end

  def init(_) do
    # ranch_listenser_child_id = String.to_atom(to_string(@ftp_server_name) <> "_ranch_listener")
    common_child_id = String.to_atom(to_string(@ftp_server_name) <> "_ranch_listener")

    children = [
      {Registry, keys: :unique, name: AcceptorRegistry},
      worker(ConnectionListener, [name: @ftp_server_name], id: common_child_id)
    ]

    options = [strategy: :one_for_one]
    Supervisor.init(children, options)
  end

  def terminate_child(name) when is_atom(name), do: to_string(name) |> terminate_child()

  def terminate_child(name) do
    ranch_listener_name = String.to_atom(name <> "_ranch_listener")
    connection_listener_name = String.to_atom(name <> "_connection_listener")
    ## This function does not return until the listener is completely stopped.
    case :ranch.stop_listener(ranch_listener_name) do
      :ok ->
        :ok

      {:error, :not_found} ->
        Logger.info("Could not find ranch listenser: #{inspect(ranch_listener_name)}")
    end

    case Supervisor.terminate_child(@name, connection_listener_name) do
      :ok ->
        :ok

      {:error, :not_found} ->
        Logger.info("Could not find child: #{inspect(connection_listener_name)}")
    end
  end
end
