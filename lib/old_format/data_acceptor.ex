defmodule DataAcceptor do
  require Logger
  use GenServer

  def start_link(ref, socket, transport, opts) do
    control_socket = Keyword.get(opts, :control_socket, {:error, :no_control_socket})
    ConnectionRouter.start_control_acceptor(control_socket, [ref, socket, transport, opts])
  end

  def start_link(args) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [args])
    {:ok, pid}
  end


  def init([ref, socket, transport, _options]) do
    :ok = :ranch.accept_ack(ref)
    Process.flag(:trap_exit, true)
    :ranch_tcp.setopts(socket, keepalive: true, active: true)
    :gen_server.enter_loop(__MODULE__, [], %{transport: transport, socket: socket})
  end


  @doc """
  Handler for when `socket` has been closed.
  """
  def handle_info({:tcp_closed, socket}, state = %{transport: transport}) do
    transport.close(socket)
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, _, _}, state = %{transport: transport, socket: socket}) do
    transport.close(socket)
    {:stop, :normal, state}
  end
end
