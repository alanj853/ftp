defmodule FtpData do
    @moduledoc """
    Documentation for Ftp.
    """
    require Logger
    use GenServer

    
    def start_link(_args = %{server_name: server_name}) do
        name = Enum.join([server_name, "_ftp_data"]) |> String.to_atom
        initial_state = %{ socket: nil, ftp_server_pid: nil, pasv_mode: false, aborted: false, server_name: name}
        GenServer.start_link(__MODULE__, initial_state, name: name)
    end
    
    def init(state= %{ socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      Process.put(:ftp_server_pid, ftp_server_pid)
      {:ok, state}
    end

    def get_state(pid) do
        GenServer.call pid, :get_state
    end

    def set_state(pid, state) do
      GenServer.call pid, {:set_state, state}
    end

    def reset_state(pid) do
      GenServer.cast pid, :reset_state
    end

    def set_server_pid(pid, ftp_server_pid) do
      GenServer.call pid, {:set_server_pid, ftp_server_pid}
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

    def handle_call({:set_server_pid, new_server_pid}, _from, state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      Process.put(:ftp_server_pid, new_server_pid)
      {:reply, state, %{socket: socket, ftp_server_pid: new_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}}
    end

    def handle_call({:set_server_pid, new_server_pid}, _from, state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      {:reply, state, %{socket: socket, ftp_server_pid: new_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}}
    end

    def handle_cast({:retr, file, new_offset} , state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      case pasv_mode do
        true ->
          pid = Process.get(:ftp_pasv_socket_pid)
          FtpPasvSocket.retr(pid, file, new_offset)
        false -> 
          pid = Process.get(:ftp_active_socket_pid)
          FtpActiveSocket.retr(pid, file, new_offset)
      end
      {:noreply, state}
    end

    def handle_cast(:reset_state , state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      case pasv_mode do
        true -> 
          Process.get(:passive_listener_name) |> :ranch.stop_listener()
        false -> 
          pid = Process.get(:ftp_active_socket_pid)
          FtpActiveSocket.reset_state(pid)
      end
      {:noreply, %{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: false, server_name: server_name}}
    end

    def handle_cast({:stor, to_path} , state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      case pasv_mode do
        true ->
          pid = Process.get(:ftp_pasv_socket_pid)
          FtpPasvSocket.stor(pid, to_path)
        false -> 
          pid = Process.get(:ftp_active_socket_pid)
          FtpActiveSocket.stor(pid, to_path)
      end
      {:noreply, state}
    end

    def handle_cast({:handle_pasv, ip, port} , state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      passive_listener_name = Enum.join([server_name, "_", "pasv_socket"]) |> String.to_atom
      case :ranch.start_listener(passive_listener_name, 10, :ranch_tcp, [port: port, ip: ip], FtpPasvSocket, [%{ftp_data_pid: self(), aborted: aborted, socket: nil}]) do
        {:ok, passive_listener_pid} ->
          logger_debug "Started new pasv socket listener: #{inspect passive_listener_pid}"
        {:error, {:already_started, passive_listener_pid}} -> 
          :ranch.stop_listener(passive_listener_name)
          :ranch.start_listener(passive_listener_name, 10, :ranch_tcp, [port: port, ip: ip], FtpPasvSocket, [%{ftp_data_pid: self(), aborted: aborted, socket: nil}])
      end
      
      Process.put(:passive_listener_name, passive_listener_name)
      state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: true, aborted: aborted, server_name: server_name}
      {:noreply, state}
    end

    def handle_cast({:list, file_info} , state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
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

    def handle_cast(:close_data_socket, state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      case pasv_mode do
        true ->
          pid = Process.get(:ftp_active_socket_pid)
          FtpActiveSocket.close_data_socket(pid)
        false ->
          pid = Process.get(:ftp_active_socket_pid)
          FtpActiveSocket.close_data_socket(pid)
      end
      {:noreply, state}
    end

    def handle_cast({:close_data_socket, :abort}, state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      case pasv_mode do
        true ->
          pid = Process.get(:ftp_pasv_socket_pid)
          FtpPasvSocket.close_data_socket(pid, :abort)
        false ->
          pid = Process.get(:ftp_active_socket_pid)
          FtpActiveSocket.close_data_socket(pid, :abort)
      end
      {:noreply, %{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: true, server_name: server_name}}
    end

    def handle_cast({:create_socket, new_ip, new_port}, state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      case pasv_mode do
        true ->
          logger_debug "No need to create socket, Passing this to pasv socket..."
          :ok 
        false ->
          logger_debug "Passing this to active socket..."
          pid =
          case FtpActiveSocket.start_link(%{ftp_data_pid: self(), aborted: false, server_name: server_name}) do
            {:ok, pid} -> pid
            {:error, {:already_started, pid}} -> pid
          end
          logger_debug "This is active socket pid #{inspect pid}..."
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
      new_state = 
      case message do
        {:ftp_pasv_socket_pid, pid} -> 
          Process.put(:ftp_pasv_socket_pid, pid)
          logger_debug "This is pid of pasv_socket GenServer: #{inspect pid}"
          state
        :close_pasv_socket -> 
          passive_listener_name = Process.get(:passive_listener_name)
          :ranch.stop_listener(passive_listener_name)
          logger_debug "Stopped pasv socket listener (closes pasv socket)"
          Map.put(state, :pasv_mode, false)
        _ -> 
          message_server(message)
          state
      end
      logger_debug("This is new state after pasv #{inspect new_state}")
      {:noreply, new_state}
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
      pid = Process.get(:ftp_server_pid)
      Kernel.send(pid, {:from_ftp_data, message})
    end

    defp logger_debug(message) do
      pid = Process.get(:ftp_server_pid)
      Kernel.send(pid, {:ftp_data_log_message, message})
    end

end