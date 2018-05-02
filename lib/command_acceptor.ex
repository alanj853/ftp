defmodule CommandAcceptor do
  require Logger
  use GenServer

  def start_link([_sup_pid, _ref, socket, _transport, _options] = args) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [args])
    Registry.register(AcceptorRegistry, {__MODULE__, socket}, pid)
    {:ok, pid}
  end

  def pid(socket) do
    [{_owner, pid}] = Registry.lookup(AcceptorRegistry, {__MODULE__, socket})
    pid
  end

  def init([sup_pid, ref, socket, transport, _options]) do
    #Registry.register_name({AcceptorRegistry, {__MODULE__, socket}}, self())
    :ok = :ranch.accept_ack(ref)
    Process.flag(:trap_exit, true)
    :ranch_tcp.setopts(socket, keepalive: true, active: true)
    transport.send(socket, "220 Welcome to FTP Server\r\n")
    :gen_server.enter_loop(__MODULE__, [], %{transport: transport, socket: socket, sup_pid: sup_pid, command_handler_state: CommandHandler.initialize(socket)})
  end

  @doc """
  Handler for all TCP messages received on `socket`.
  """
  def handle_info({:tcp, socket, "QUIT\r\n"}, state = %{transport: transport, sup_pid: sup_pid}) do
    transport.close(socket)
    Supervisor.stop(sup_pid)
    {:stop, :normal, state}
  end

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

  def handle_info({:EXIT, _, _}, state = %{transport: transport, socket: socket, sup_pid: sup_pid}) do
    transport.close(socket)
    Supervisor.stop(sup_pid)
    {:stop, :normal, state}
  end
end

defmodule CommandHandler do
  use Fsm, initial_state: :awaiting_auth

  defmodule Data do
    defstruct username: nil, control_ip: nil, data_ip: nil, data_port: nil, socket: nil
  end

  def initialize(socket) do
    {:ok, {control_ip, _port}} = :inet.sockname(socket)
    %__MODULE__{data: %__MODULE__.Data{control_ip: control_ip, socket: socket}}
  end

  defstate awaiting_auth do
    defevent handle_packet(<<"USER ", username::binary>>), data: data do
      username = to_string(username) |> String.trim()
      respond("331 Enter Password\r\n", :awaiting_password, %{data | username: username})
    end
  end

  defstate awaiting_password do
    defevent handle_packet(<<"PASS ", _password::binary>>) do
      respond("230 User Authenticated\r\n", :authorized)
    end
  end

  defstate authorized do
    defevent handle_packet(<<"PASV", _::binary>>), data: %{control_ip: control_ip, socket: socket} = data do
        p1 = :rand.uniform(230) + 2
        p2 = :rand.uniform(230)
        port_number = p1*256 + p2
        ip = control_ip
        data = %{
          data
          | data_ip: ip,  ## update data socket info with new ip
          data_port: port_number ## update data socket info with new port_number
        }
        {h1, h2, h3, h4} = ip
      ConnectionRouter.start_data_listener(socket, ip, port_number)
      respond("227 Entering Passive Mode (#{inspect h1},#{inspect h2},#{inspect h3},#{inspect h4},#{inspect p1},#{inspect p2})\r\n", :passive_mode, data)
    end
  end

  defstate passive_mode do
  end
end
