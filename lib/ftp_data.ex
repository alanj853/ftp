defmodule FtpData do
    @moduledoc """
    Documentation for Ftp.
    """
   
    @server_name __MODULE__
    @debug true
    require Logger
    use GenServer

    #socket, ip, port, offset

    def start_link() do
        initial_state = %{ socket: nil, server_pid: nil}
        GenServer.start_link(__MODULE__, initial_state, name: @server_name)
    end
    
      def init(state) do
        {:ok, state}
      end

      def get_state(pid) do
          GenServer.call pid, :get_state
      end

      def set_server_pid(pid, server_pid) do
        GenServer.call pid, {:set_server_pid, server_pid}
      end

      def handle_call(:get_state, _from, state) do
        {:reply, state, state}
      end

      def retr(pid, file, offset) do
        GenServer.cast pid, {:retr, file, offset}
      end

      def close_socket(pid) do
        GenServer.call pid, :close_socket
      end

      def create_socket(pid, new_ip, new_port) do
        GenServer.call pid, {:create_socket, new_ip, new_port}
      end

      def handle_call({:set_server_pid, new_server_pid}, _from, state=%{socket: socket, server_pid: server_pid}) do
        {:reply, state, %{socket: socket, server_pid: new_server_pid}}
      end

      def handle_cast({:retr, file, new_offset} , state=%{socket: socket, server_pid: server_pid}) do
        Logger.info "Sending file..."
        :ranch_tcp.sendfile(socket, file, new_offset, 0)
        Logger.info "File sent."
        message_parent(server_pid, {:from_data_socket, :socket_transfer_ok})
        :ranch_tcp.close(socket)
        new_state=%{socket: nil, server_pid: server_pid}
        {:noreply, new_state}
      end

      def handle_call(:close_socket, _from, state=%{socket: socket, server_pid: server_pid}) do
        case socket do
          nil -> :ok
          _ -> :ranch_tcp.close(socket)
        end
        message_parent(server_pid, {:from_data_socket, :socket_close_ok})
        new_state = %{socket: nil, server_pid: server_pid}
        {:reply, state, new_state}
      end

      def handle_call({:create_socket, new_ip, new_port}, _from, state=%{socket: socket, server_pid: server_pid}) do
        IO.puts "Connecting  to #{inspect new_ip}:#{inspect new_port}"
        {:ok, data_socket} = :gen_tcp.connect(new_ip, new_port ,[active: false, mode: :binary, packet: :raw]) 
        message_parent(server_pid, {:from_data_socket, :socket_create_ok}) 
        new_state = %{socket: data_socket, server_pid: server_pid}
        {:reply, state, new_state}
      end

      def message_parent(pid, message) do
        IO.puts "Messagin parent #{inspect pid} with message #{inspect message}"
        Kernel.send(pid, message)
        IO.puts "Messag sent"
      end

end