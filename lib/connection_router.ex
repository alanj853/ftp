defmodule ConnectionRouter do
  use DynamicSupervisor

  def start_link([socket]) do
    DynamicSupervisor.start_link(__MODULE__, [], name: name(socket))
  end

  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_all(socket) do
    DynamicSupervisor.start_child(name(socket), {Agent, fn -> nil end})
  end

  def start_data_listener(socket, ip, port) do
      spec = :ranch.child_spec(
        "data_socket_#{port}",
        1,
        :ranch_tcp,
        [port: port, ip: ip, connection_type: :supervisor, max_connections: 1],
        DataAcceptor,
        [control_socket: socket]
      )

    DynamicSupervisor.start_child(name(socket), spec)
  end

  def start_control_acceptor(socket, args) do
    sup_pid = GenServer.whereis(name(socket))
    {:ok, data_pid} = DynamicSupervisor.start_child(sup_pid, {DataAcceptor, args})
    {:ok, sup_pid, data_pid}
  end

  def name(socket) do
    {:via, Registry, {AcceptorRegistry, {__MODULE__, socket}}}
  end
end
