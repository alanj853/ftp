defmodule FtpData do
    @moduledoc """
    Documentation for Ftp.
    """
    require Logger
    use GenServer

    @server_name __MODULE__
    @debug 2
    
    def start_link() do
        initial_state = %{ socket: nil, server_pid: nil, pasv_mode: false, aborted: false}
        GenServer.start_link(__MODULE__, initial_state, name: @server_name)
    end
    
    def init(state) do
      {:ok, state}
    end

    def get_state(pid) do
        GenServer.call pid, :get_state
    end

    def set_state(pid, state) do
      GenServer.call pid, {:set_state, state}
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

    def pasv(pid, ip, port) do
      GenServer.cast pid, {:handle_pasv, ip, port}
    end 

    def close_data_socket(pid) do
      GenServer.call pid, {:close_data_socket}
    end

    def close_data_socket(pid, reason) do
      GenServer.call pid, {:close_data_socket, reason}
    end

    def create_socket(pid, new_ip, new_port) do
      GenServer.call pid, {:create_socket, new_ip, new_port}
    end

    def handle_call({:set_state, new_state}, _from, state) do
      {:reply, state, new_state}
    end

    def handle_call({:set_server_pid, new_server_pid}, _from, state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      {:reply, state, %{socket: socket, server_pid: new_server_pid, pasv_mode: pasv_mode, aborted: aborted}}
    end

    def handle_call({:set_server_pid, new_server_pid}, _from, state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      {:reply, state, %{socket: socket, server_pid: new_server_pid, pasv_mode: pasv_mode, aborted: aborted}}
    end

    def handle_cast({:retr, file, new_offset} , state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      logger_debug "[DATA_SOCKET #{inspect socket}] Sending file..."
      case :ranch_tcp.sendfile(socket, file, new_offset, 0) do
        {:ok, exit_code} ->
          logger_debug "[DATA_SOCKET #{inspect socket}] File sent."
          message_server(server_pid, {:from_data_socket, :socket_transfer_ok})
        {:error, reason} -> 
          logger_debug "[DATA_SOCKET #{inspect socket}] File not sent. Reason: #{inspect reason}"
          message_server(server_pid, {:from_data_socket, :socket_transfer_failed})
      end
      
      new_state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}
      {:noreply, new_state}
    end

    def handle_cast({:stor, to_path} , state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      logger_debug "[DATA_SOCKET #{inspect socket}] Receiving file..."
      {:ok, file} = receive_file(socket)
      logger_debug("This is packet: #{inspect file}")
      file_size = byte_size(file)
      logger_debug("This is size: #{inspect file_size}")
      :file.write_file(to_charlist(to_path), file)
      logger_debug "[DATA_SOCKET #{inspect socket}] File received."
      message_server(server_pid, {:from_data_socket, :socket_transfer_ok})
      close_socket(socket)
      new_state=%{socket: nil, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}
      {:noreply, new_state}
    end

    def handle_cast({:list, file_info} , state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      logger_debug "[DATA_SOCKET #{inspect socket}] Sending result from LIST command..."
      :gen_tcp.send(socket, file_info)
      logger_debug "[DATA_SOCKET #{inspect socket}] Result from LIST command sent."
      message_server(server_pid, {:from_data_socket, :socket_transfer_ok})
      close_socket(socket)
      new_state=%{socket: nil, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}
      {:noreply, new_state}
    end

    def handle_call(:close_data_socket, _from, state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      logger_debug "[DATA_SOCKET #{inspect socket}] Closing data Socket..."
      close_socket(socket)
      message_server(server_pid, {:from_data_socket, :socket_close_ok})
      logger_debug "[DATA_SOCKET #{inspect socket}] Socket Closed."
      new_state = %{socket: nil, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}
      {:reply, state, new_state}
    end

    def handle_call({:close_data_socket, :abort}, _from, state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      logger_debug "[DATA_SOCKET #{inspect socket}] Closing data Socket (due to abort command)..."
      close_socket(socket)
      new_state = %{socket: nil, server_pid: server_pid, pasv_mode: pasv_mode, aborted: true}
      {:reply, state, new_state}
    end

    def handle_call({:create_socket, new_ip, new_port}, _from, state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      new_state = 
      case pasv_mode do
        true ->
          logger_debug "[DATA_SOCKET #{inspect socket}] In passive mode, socket has already been created."
          state
        false ->
          logger_debug "[DATA_SOCKET #{inspect socket}] Connecting  to #{inspect new_ip}:#{inspect new_port}"
          {:ok, socket} = :gen_tcp.connect(new_ip, new_port ,[active: false, mode: :binary, packet: :raw]) 
          message_server(server_pid, {:from_data_socket, :socket_create_ok})
          %{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}
      end
      {:reply, state, new_state}
    end

    def handle_cast({:handle_pasv, ip, port} , state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      logger_debug "[DATA_SOCKET #{inspect socket}] Setting up listening data socket on request of PASV command..."
      case :gen_tcp.listen(port, [ip: ip, active: false, backlog: 1024, nodelay: true, send_timeout: 30000, send_timeout_close: true]) do
        {:ok, lsocket} ->
          case :gen_tcp.accept(lsocket) do
            {:ok, new_socket} ->
              socket = new_socket
              logger_debug "[DATA_SOCKET #{inspect new_socket}] Got Connection"
            {:error, reason} -> logger_debug "Got error while listening #{reason}"
        end
        {:error, reason} -> 
            logger_debug "[DATA_SOCKET #{inspect socket}] Error setting up listen socket. Reason: #{reason}"
            nil
      end
      new_state=%{socket: socket, server_pid: server_pid, pasv_mode: true, aborted: false}
      {:noreply, new_state}
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

  defp close_socket(socket) do
      case (socket == nil) do
          true -> logger_debug "[DATA_SOCKET #{inspect socket}] Socket #{inspect socket} already closed."
          false ->
              case :ranch_tcp.shutdown(socket, :read_write) do
                  :ok -> logger_debug "[DATA_SOCKET #{inspect socket}] Socket #{inspect socket} successfully closed."
                  {:error, closed} -> logger_debug "[DATA_SOCKET #{inspect socket}] Socket #{inspect socket} already closed."
                  {:error, other_reason} -> logger_debug "[DATA_SOCKET #{inspect socket}] Error while attempting to close socket #{inspect socket}. Reason: #{other_reason}."
              end
      end
  end

end