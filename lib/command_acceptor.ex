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
    :ranch_tcp.setopts(socket, keepalive: true, active: true)
    transport.send(socket, "220 Welcome to FTP Server\r\n")
    :gen_server.enter_loop(__MODULE__, [], %{transport: transport, sup_pid: sup_pid, command_handler_state: CommandHandler.new})
  end

  @doc """
  Handler for all TCP messages received on `socket`.
  """
  def handle_info({:tcp, socket, packet}, state = %{transport: transport, command_handler_state: command_handler_state}) do
    {response, command_handler_state} = CommandHandler.handle_packet(command_handler_state, packet)
    transport.send(socket, response)
    {:noreply, %{state | command_handler_state: command_handler_state}}
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

defmodule CommandHandler do
  use Fsm, initial_state: :awaiting_auth

  defstate awaiting_auth do
    defevent handle_packet(<<"USER ", username::binary>>) do
      username = to_string(username) |> String.trim()
      respond("331 Enter Password\r\n", :awaiting_password, username)
    end
  end

  defstate awaiting_password do
    defevent handle_packet(<<"PASS ", password::binary>>), data: username do
      to_string(password) |> String.trim() |> IO.inspect
      respond("230 User Authenticated\r\n", :done)
    end
  end
end
