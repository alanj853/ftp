defmodule FtpData do
    @moduledoc """
    Documentation for Ftp.
    """
    require Logger
    use GenServer

    @server_name __MODULE__
    @debug 2
    
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

    def stor(pid, to_path) do
      GenServer.cast pid, {:stor, to_path}
    end

    def list(pid, path) do
      GenServer.cast pid, {:list, path}
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
      logger_debug "[DATA_SOCKET #{inspect socket}] Sending file..."
      case :ranch_tcp.sendfile(socket, file, new_offset, 0) do
        {:ok, exit_code} ->
          logger_debug "[DATA_SOCKET #{inspect socket}] File sent."
          message_server(server_pid, {:from_data_socket, :socket_transfer_ok})
        {:error, reason} -> 
          logger_debug "[DATA_SOCKET #{inspect socket}] File not sent. Reason: #{inspect reason}"
          message_server(server_pid, {:from_data_socket, :socket_transfer_failed})
      end
      
      :gen_tcp.close(socket)
      new_state=%{socket: nil, server_pid: server_pid}
      {:noreply, new_state}
    end

    def handle_cast({:stor, to_path} , state=%{socket: socket, server_pid: server_pid}) do
      logger_debug "[DATA_SOCKET #{inspect socket}] Receiving file..."
      {:ok, file} = receive_file(socket)
      logger_debug("This is packet: #{inspect file}")
      file_size = byte_size(file)
      logger_debug("This is size: #{inspect file_size}")
      :file.write_file(to_charlist(to_path), file)
      logger_debug "[DATA_SOCKET #{inspect socket}] File received."
      message_server(server_pid, {:from_data_socket, :socket_transfer_ok})
      :gen_tcp.close(socket)
      new_state=%{socket: nil, server_pid: server_pid}
      {:noreply, new_state}
    end

    def handle_cast({:list, file_info} , state=%{socket: socket, server_pid: server_pid}) do
      logger_debug "[DATA_SOCKET #{inspect socket}] Sending result from LIST command..."
      :gen_tcp.send(socket, file_info)
      logger_debug "[DATA_SOCKET #{inspect socket}] Result from LIST command sent."
      message_server(server_pid, {:from_data_socket, :socket_transfer_ok})
      :gen_tcp.close(socket)
      new_state=%{socket: nil, server_pid: server_pid}
      {:noreply, new_state}
    end

    def handle_call(:close_socket, _from, state=%{socket: socket, server_pid: server_pid}) do
      logger_debug "[DATA_SOCKET #{inspect socket}] Closing data Socket..."
      case socket do
        nil -> :ok
        _ -> :gen_tcp.close(socket)
      end
      message_server(server_pid, {:from_data_socket, :socket_close_ok})
      logger_debug "[DATA_SOCKET #{inspect socket}] Socket Closed."
      new_state = %{socket: nil, server_pid: server_pid}
      {:reply, state, new_state}
    end

    def handle_call({:create_socket, new_ip, new_port}, _from, state=%{socket: socket, server_pid: server_pid}) do
      logger_debug "[DATA_SOCKET #{inspect socket}] Connecting  to #{inspect new_ip}:#{inspect new_port}"
      {:ok, socket} = :gen_tcp.connect(new_ip, new_port ,[active: false, mode: :binary, packet: :raw]) 
      message_server(server_pid, {:from_data_socket, :socket_create_ok}) 
      new_state = %{socket: socket, server_pid: server_pid}
      {:reply, state, new_state}
    end

    defp message_server(pid, message) do
      Kernel.send(pid, message)
    end

    defp logger_debug(message, id \\ "") do
      case @debug do
          0 -> :ok
          _ -> Enum.join([" [FTP]   ", message]) |> Logger.debug
      end
    end

    defp receive_file(socket, packet \\ "") do
      case :gen_tcp.recv(socket, 0) do
          {:ok, new_packet} ->
              new_packet = Enum.join([packet, new_packet])
              receive_file(socket, new_packet)
          {:error, :closed} ->
            logger_debug "[DATA_SOCKET #{inspect socket}] Finished receiving file."
              {:ok, packet}
          {:error, other_reason} ->
            logger_debug "[DATA_SOCKET #{inspect socket}] Error receiving file: #{other_reason}"
              {:ok, packet}
      end
    end

end