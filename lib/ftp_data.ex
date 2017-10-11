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
    
    def init(state= %{ socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      Process.put(:server_pid, server_pid)
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
      GenServer.cast pid, {:close_data_socket}
    end

    def close_data_socket(pid, reason) do
      GenServer.cast pid, {:close_data_socket, reason}
    end

    def create_socket(pid, new_ip, new_port) do
      GenServer.cast pid, {:create_socket, new_ip, new_port}
    end

    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end

    def handle_call({:set_state, new_state}, _from, state) do
      {:reply, state, new_state}
    end

    def handle_call({:set_server_pid, new_server_pid}, _from, state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      Process.put(:server_pid, new_server_pid)
      {:reply, state, %{socket: socket, server_pid: new_server_pid, pasv_mode: pasv_mode, aborted: aborted}}
    end

    def handle_call({:set_server_pid, new_server_pid}, _from, state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      {:reply, state, %{socket: socket, server_pid: new_server_pid, pasv_mode: pasv_mode, aborted: aborted}}
    end

    def handle_cast({:retr, file, new_offset} , state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      case pasv_mode do
        true -> :ok
        false -> 
          pid = Process.get(:ftp_active_socket_pid)
          FtpActiveSocket.retr(pid, file, new_offset)
      end
      {:noreply, state}
    end

    def handle_cast({:stor, to_path} , state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      case pasv_mode do
        true -> :ok
        false -> 
          pid = Process.get(:ftp_active_socket_pid)
          FtpActiveSocket.stor(pid, to_path)
      end
      {:noreply, state}
    end

    def handle_cast({:handle_pasv, ip, port} , state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      :ranch.start_listener(:pasv_socket, 10, :ranch_tcp, [port: port, ip: ip], FtpPasvSocket, [%{ftp_data_pid: self(), aborted: aborted}])
      pid = Process.get(:ftp_pasv_socket_pid)
      state=%{socket: socket, server_pid: server_pid, pasv_mode: true, aborted: aborted}
      {:noreply, state}
    end

    def handle_cast({:list, file_info} , state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      case pasv_mode do
        true ->
          pid = Process.get(:ftp_pasv_socket_pid)
          logger_debug "Passing this to pasv socket #{inspect pid}..."
          FtpPasvSocket.list(pid ,file_info)
        false -> 
          pid = Process.get(:ftp_active_socket_pid)
          logger_debug "Passing this to active socket #{inspect pid}..."
          FtpActiveSocket.list(pid ,file_info)
      end
      {:noreply, state}
    end

    def handle_cast(:close_data_socket, state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      case pasv_mode do
        true ->
          :ok 
        false ->
          pid = Process.get(:ftp_active_socket_pid)
          FtpActiveSocket.close_data_socket(pid)
      end
      {:noreply, state}
    end

    def handle_cast({:close_data_socket, :abort}, state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      case pasv_mode do
        true ->
          :ok 
        false ->
          pid = Process.get(:ftp_active_socket_pid)
          FtpActiveSocket.close_data_socket(pid, :abort)
      end
      {:noreply, %{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: true}}
    end

    def handle_cast({:create_socket, new_ip, new_port}, state=%{socket: socket, server_pid: server_pid, pasv_mode: pasv_mode, aborted: aborted}) do
      case pasv_mode do
        true ->
          :ok 
        false ->
          logger_debug "Passing this to active socket..."
          pid =
          case FtpActiveSocket.start_link(%{ftp_data_pid: self(), aborted: false}) do
            {:ok, pid} -> pid
            {:error, {:already_started, pid}} -> pid
          end
          Process.put(:ftp_active_socket_pid, pid)
          FtpActiveSocket.create_socket(pid, new_ip, new_port)
      end
      {:noreply, state}
    end

    ## Functions to Receive functional messages from Data Sockets
    ## These get passed to the message_server function

    def handle_info({:from_active_socket, message}, state) do
      message_server(message)
      {:noreply, state}
    end

    def handle_info({:from_pasv_socket, message}, state) do
      case message do
        {:ftp_pasv_socket_pid, pid} -> Process.put(:ftp_pasv_socket_pid, pid)
        _ -> message_server(message)
      end
      {:noreply, state}
    end

    ## Functions to Receive log messages from Data Sockets.
    ## These get passed to the logger_debug function

    def handle_info({:ftp_pasv_log_message, message}, state) do
      Enum.join([" [FTP_PASV]   ", message]) |> logger_debug
      {:noreply, state}
  end

  def handle_info({:ftp_active_log_message, message}, state) do
    Enum.join([" [FTP_ACTV]   ", message]) |> logger_debug
    {:noreply, state}
end


    ## HELPER FUNCTIONS

    defp message_server(message) do
      pid = Process.get(:server_pid)
      Kernel.send(pid, {:from_ftp_data, message})
    end

    defp logger_debug(message) do
      pid = Process.get(:server_pid)
      Kernel.send(pid, {:ftp_data_log_message, message})
    end

end