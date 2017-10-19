defmodule FtpActiveSocket do
    @moduledoc """
    Documentation for FtpActiveSocket
    """
    require Logger
    use GenServer

    @server_name __MODULE__
    
    def start_link(state = %{ftp_data_pid: ftp_data_pid, aborted: aborted}) do
        initial_state = %{ socket: nil, ftp_data_pid: ftp_data_pid, aborted: aborted}
        GenServer.start_link(__MODULE__, initial_state, name: @server_name)
    end
    
    def init(state = %{ socket: socket, ftp_data_pid: ftp_data_pid, aborted: aborted}) do
        Process.put(:ftp_data_pid, ftp_data_pid)
        {:ok, state}
    end

    def reset_state(pid) do
      GenServer.cast pid, :reset_state
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

    def close_data_socket(pid) do
      GenServer.call pid, {:close_data_socket}
    end

    def close_data_socket(pid, reason) do
      GenServer.call pid, {:close_data_socket, reason}
    end

    def create_socket(pid, new_ip, new_port) do
      GenServer.call pid, {:create_socket, new_ip, new_port}
    end

    def handle_cast(:reset_state, state=%{socket: socket, ftp_data_pid: ftp_data_pid, aborted: aborted}) do
      logger_debug "Resetting Active Socket Server State"
      {:noreply, %{socket: nil, ftp_data_pid: ftp_data_pid, aborted: false}}
    end

    def handle_cast({:retr, file, new_offset} , state=%{socket: socket, ftp_data_pid: ftp_data_pid, aborted: aborted}) do
      file_info = transfer_info(file, 512, new_offset)
      logger_debug "Sending file (#{inspect file_info})..."
      send_file(socket, file, file_info, new_offset, 512, 1)
      new_state=%{socket: socket, ftp_data_pid: ftp_data_pid, aborted: aborted}
      {:noreply, new_state}
    end

    def handle_info({:send, {socket, file, file_info, new_offset, bytes, transmission_number}}, state) do
      new_socket = socket
      was_aborted = false
      aborted = Map.get(state, :aborted)
      case aborted do
        false ->
          send_file(socket, file, file_info, new_offset, bytes, transmission_number)
        true ->
          logger_debug "Aborting this transfer"
          new_socket = close_socket(socket)
          was_aborted = true
          message_ftp_data(:socket_transfer_failed)
      end
      ftp_data_pid =  Process.get(:ftp_data_pid)
      {:noreply, %{socket: new_socket, ftp_data_pid: ftp_data_pid, aborted: was_aborted}}
    end

    def transfer_info(file, chunk_size, offset) do
      {:ok, info} = File.stat(file)
      file_size = Map.get(info, :size) - offset
      no_transmissions_needed = Integer.floor_div((file_size), chunk_size) + 1
      last_transmission_size = file_size - (no_transmissions_needed-1)*chunk_size
      logger_debug "For filesize #{inspect file_size}  number of transmissions real = #{inspect no_transmissions_needed}   last_transmission_size = #{last_transmission_size}"
      %{file_size: file_size, transmissions: no_transmissions_needed, last_transmission_size: last_transmission_size}
    end

    defp send_file(socket, file, file_info, offset, bytes, transmission_number) do
      cond do
        transmission_number == (Map.get(file_info,:transmissions)+1) ->
          logger_debug "file sent"
          message_ftp_data(:socket_transfer_ok)
          close_socket(socket)
          :whole_file_sent
        transmission_number == (Map.get(file_info,:transmissions)) -> 
          bytes = Map.get(file_info,:last_transmission_size)
          send_chunk(socket, file, offset, bytes)
          new_offset = offset+bytes
          transmission_number = transmission_number+1
          Kernel.send(self(), {:send, {socket, file, file_info, new_offset, bytes, transmission_number}}) 
        true ->
          send_chunk(socket, file, offset, bytes)
          new_offset = offset+bytes
          transmission_number = transmission_number+1
          Kernel.send(self(), {:send, {socket, file, file_info, new_offset, bytes, transmission_number}}) 
      end
           
    end

    defp send_chunk(socket, file, offset, bytes) do
      #logger_debug "trying to send chunk for #{inspect bytes} from offset #{offset}"
      case :ranch_tcp.sendfile(socket, file, offset, bytes) do
        {:ok, exit_code} -> :chunk_sent
        {:error, reason} -> :chunk_not_sent
      end
    end

    def handle_cast({:stor, to_path} , state=%{socket: socket, ftp_data_pid: ftp_data_pid, aborted: aborted}) do
      logger_debug "Receiving file..."
      {:ok, file} = receive_file(socket)
      logger_debug("This is packet: #{inspect file}")
      file_size = byte_size(file)
      logger_debug("This is size: #{inspect file_size}")
      :file.write_file(to_charlist(to_path), file)
      logger_debug "File received."
      message_ftp_data(:socket_transfer_ok)
      new_socket_state = close_socket(socket)
      new_state=%{socket: new_socket_state, ftp_data_pid: ftp_data_pid, aborted: aborted}
      {:noreply, new_state}
    end

    def handle_cast({:list, file_info} , state=%{socket: socket, ftp_data_pid: ftp_data_pid, aborted: aborted}) do
      logger_debug "Sending result from LIST command..."
      :gen_tcp.send(socket, file_info)
      logger_debug "Result from LIST command sent. Sent #{inspect file_info}"
      message_ftp_data(:socket_transfer_ok)
      new_socket_state = close_socket(socket)
      new_state=%{socket: new_socket_state, ftp_data_pid: ftp_data_pid, aborted: aborted}
      {:noreply, new_state}
    end

    def handle_call(:close_data_socket, _from, state=%{socket: socket, ftp_data_pid: ftp_data_pid, aborted: aborted}) do
      logger_debug "Closing Data Socket..."
      new_socket_state = close_socket(socket)
      message_ftp_data(:socket_close_ok)
      new_state = %{socket: new_socket_state, ftp_data_pid: ftp_data_pid, aborted: aborted}
      {:reply, state, new_state}
    end

    def handle_call({:close_data_socket, :abort}, _from, state=%{socket: socket, ftp_data_pid: ftp_data_pid, aborted: aborted}) do
      logger_debug "Closing Data Socket (due to abort command)..."
      #new_socket_state = close_socket(socket)
      new_state = %{socket: socket, ftp_data_pid: ftp_data_pid, aborted: true}
      {:reply, state, new_state}
    end

    def handle_call({:create_socket, new_ip, new_port}, _from, state=%{socket: socket, ftp_data_pid: ftp_data_pid, aborted: aborted}) do
      logger_debug "Connecting  to #{inspect new_ip}:#{inspect new_port}"
      {:ok, socket} = :ranch_tcp.connect(new_ip, new_port ,[active: false, mode: :binary, packet: :raw, exit_on_close: true, linger: {true, 100}]) 
      socket_status = Port.info(socket)
      logger_debug "This is new data_socket #{inspect socket} info: #{inspect socket_status}"
      message_ftp_data(:socket_create_ok)
      new_state = %{socket: socket, ftp_data_pid: ftp_data_pid, aborted: aborted}
      {:reply, state, new_state}
    end

    def handle_info({:from_ftp_data, message}, state) do
      {:noreply, state}
    end


    ## HELPER FUNCTIONS

    defp message_ftp_data(message) do
        pid = Process.get(:ftp_data_pid)
      Kernel.send(pid, {:from_active_socket, message})
    end

    defp logger_debug(message, id \\ "") do
        pid = Process.get(:ftp_data_pid)
        Kernel.send(pid, {:ftp_active_log_message, message})
    end

    defp receive_file(socket, packet \\ "") do
      case :gen_tcp.recv(socket, 0) do
          {:ok, new_packet} ->
              new_packet = Enum.join([packet, new_packet])
              receive_file(socket, new_packet)
          {:error, :closed} ->
            logger_debug "Finished receiving file."
              {:ok, packet}
          {:error, other_reason} ->
            logger_debug "Error receiving file: #{other_reason}"
              {:ok, packet}
      end
    end

  defp close_socket(socket) do
    case (socket == nil) do
          true ->
            logger_debug "Data Socket #{inspect socket} already closed."
            nil
          false ->
              case :ranch_tcp.shutdown(socket, :read_write) do
                  :ok ->
                    logger_debug "Data Socket #{inspect socket} successfully closed."
                    nil
                  {:error, closed} -> 
                    logger_debug "Data Socket #{inspect socket} already closed."
                    nil
                  {:error, other_reason} -> 
                    logger_debug "Error while attempting to close Data Socket #{inspect socket}. Reason: #{other_reason}."
                    socket
              end
      end
  end

end