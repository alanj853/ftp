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
    
    def set_server_pid(pid, ftp_server_pid) do
      GenServer.call pid, {:set_server_pid, ftp_server_pid}
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

    def handle_info({:retr, file, new_offset} , state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      case pasv_mode do
        true -> 
          case Process.get(:ftp_pasv_socket_pid) do
            nil ->
              #logger_debug "Waiting for FtpPasvSocket GenServer to come available"
              Kernel.send(self(), {:retr, file, new_offset})
            pid ->
              FtpPasvSocket.retr(pid, file, new_offset)
          end
        false -> Process.get(:ftp_active_socket_pid) |> FtpActiveSocket.retr(file, new_offset)
      end
      {:noreply, state}
    end

    def handle_info(:reset_state , state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      case pasv_mode do
        true -> 
          case Process.get(:ftp_pasv_socket_pid) do
            nil ->
              #logger_debug "Waiting for FtpPasvSocket GenServer to come available"
              Kernel.send(self(), :reset_state )
            pid ->
              Process.get(:passive_listener_name) |> :ranch.stop_listener()
          end
        false -> Process.get(:ftp_active_socket_pid) |> FtpActiveSocket.reset_state()
      end
      {:noreply, %{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: false, server_name: server_name}}
    end

    def handle_info({:stor, to_path} , state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      case pasv_mode do
        true -> 
          case Process.get(:ftp_pasv_socket_pid) do
            nil ->
              #logger_debug "Waiting for FtpPasvSocket GenServer to come available"
              Kernel.send(self(), {:stor, to_path})
            pid ->
              FtpPasvSocket.stor(pid, to_path)
          end
        false -> Process.get(:ftp_active_socket_pid) |> FtpActiveSocket.stor(to_path)
      end
      {:noreply, state}
    end

    def handle_info({:pasv, ip, port} , state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      passive_listener_name = Enum.join([server_name, "_", "pasv_socket"]) |> String.to_atom
      case :ranch.start_listener(passive_listener_name, 10, :ranch_tcp, [port: port, ip: ip], FtpPasvSocket, [%{ftp_data_pid: self(), aborted: aborted, socket: nil, server_name: server_name}]) do
        {:ok, passive_listener_pid} ->
          logger_debug "Started new pasv socket listener: #{inspect passive_listener_pid}"
        {:error, {:already_started, passive_listener_pid}} -> 
          :ranch.stop_listener(passive_listener_name)
          :ranch.start_listener(passive_listener_name, 10, :ranch_tcp, [port: port, ip: ip], FtpPasvSocket, [%{ftp_data_pid: self(), aborted: aborted, socket: nil, server_name: server_name}])
      end
      
      Process.put(:passive_listener_name, passive_listener_name)
      state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: true, aborted: aborted, server_name: server_name}
      {:noreply, state}
    end

    def handle_info({:list, file_info} , state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      case pasv_mode do
        true ->
          case Process.get(:ftp_pasv_socket_pid) do
            nil ->
              #logger_debug "Waiting for FtpPasvSocket GenServer to come available"
              Kernel.send(self(), {:list, file_info} )
            pid -> 
              logger_debug "Passing this to pasv socket #{inspect pid}..."
              FtpPasvSocket.list(pid ,file_info)
          end
          
        false -> 
          pid = Process.get(:ftp_active_socket_pid)
          logger_debug "Passing this to active socket #{inspect pid}..."
          FtpActiveSocket.list(pid ,file_info)
      end
      {:noreply, state}
    end

    def handle_info(:close_data_socket, state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      case pasv_mode do
        true -> 
          case Process.get(:ftp_pasv_socket_pid) do
            nil ->
              #logger_debug "Waiting for FtpPasvSocket GenServer to come available"
              Kernel.send(self(), :close_data_socket)
            pid ->
              FtpActiveSocket.close_data_socket(pid)
          end
        false -> Process.get(:ftp_active_socket_pid) |> FtpActiveSocket.close_data_socket()
      end
      {:noreply, state}
    end

    def handle_info({:close_data_socket, :abort}, state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
      case pasv_mode do
        true -> 
          case Process.get(:ftp_pasv_socket_pid) do
            nil ->
              #logger_debug "Waiting for FtpPasvSocket GenServer to come available"
              Kernel.send(self(), {:close_data_socket, :abort})
            pid ->
              FtpPasvSocket.close_data_socket(pid, :abort)
          end
        false -> Process.get(:ftp_active_socket_pid) |> FtpActiveSocket.close_data_socket(:abort)
      end
      {:noreply, %{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: true, server_name: server_name}}
    end

    def handle_info({:create_socket, new_ip, new_port}, state=%{socket: socket, ftp_server_pid: ftp_server_pid, pasv_mode: pasv_mode, aborted: aborted, server_name: server_name}) do
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
      Process.get(:ftp_server_pid) |> Kernel.send({:from_ftp_data, message})
    end

    defp logger_debug(message) do
      Process.get(:ftp_server_pid) |> Kernel.send({:ftp_data_log_message, message})
    end

end