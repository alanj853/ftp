defmodule CommandAcceptor do
  require Logger
  use GenServer

  def start_link(args) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [args])
    {:ok, pid}
  end

  def name(socket) do
    {:via, Registry, {AcceptorRegistry, {__MODULE__, socket}}}
  end

  def init([sup_pid, ref, socket, transport, _options]) do
    Registry.register_name({AcceptorRegistry, {__MODULE__, socket}}, self())
    :ok = :ranch.accept_ack(ref)
    :ranch_tcp.setopts(socket, active: true)
    ConnectionRouter.start_all(socket)
    :gen_server.enter_loop(__MODULE__, [], %{transport: transport, sup_pid: sup_pid})
  end

  @doc """
  Handler for all TCP messages received on `socket`.
  """
  def handle_info({:tcp, socket, packet}, state = %{transport: transport}) do
    transport.send(socket, packet)
    {:noreply, state}
  end

  @doc """
  Handler for when `socket` has been closed.
  """
  def handle_info({:tcp_closed, socket}, state = %{transport: transport, sup_pid: sup_pid}) do
    transport.close(socket)
    Supervisor.stop(sup_pid)
    {:stop, :normal, state}
  end
end
