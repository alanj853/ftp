defmodule FtpPasvSocket do
    @moduledoc """
    Documentation for FtpActiveSocket
    """
    require Logger
    use GenServer

    @server_name __MODULE__
    
    def start_link(ref, socket, transport, opts = [%{ftp_data_pid: ftp_data_pid, aborted: aborted, socket: initial_socket, server_name: server_name}]) do
        new_server_name = Enum.join([server_name, "_", "ftp_pasv_socket"])
        initial_state = %{ftp_data_pid: ftp_data_pid, aborted: aborted, socket: socket, server_name: new_server_name}
        pid  = :proc_lib.spawn_link(__MODULE__, :init, [ref, socket, transport, initial_state])
        {:ok, pid}
    end

    def init(ref, socket, transport, state) do
        start_listener(ref,socket, state)
        :gen_server.enter_loop(__MODULE__, [], state)
        {:ok, %{}}
    end  

    def start_listener(ref,socket, state) do
        ftp_data_pid = Map.get(state, :ftp_data_pid)
        Process.put(:ftp_data_pid, ftp_data_pid)
        logger_debug "Ftp Passive Starting..."
        message_ftp_data({:ftp_pasv_socket_pid, self()}) ## tell parent my pid
        :ranch.accept_ack(ref)
        logger_debug "Got Connection on Passive socket"
    end

    def retr(pid, file, offset) do
        GenServer.cast pid, {:retr, file, offset}
    end
  
    def close_data_socket(pid, reason) do
        GenServer.call pid, {:close_data_socket, reason}
    end
  
    def list(pid, file_info) do
        GenServer.cast pid, {:list, file_info}
    end

    def stor(pid, to_path) do
        GenServer.cast pid, {:stor, to_path}
    end
    
    def handle_call({:close_data_socket, :abort}, _from, state=%{socket: socket, ftp_data_pid: ftp_data_pid, aborted: _aborted, server_name: server_name}) do
        logger_debug "Closing Data Socket (due to abort command)..."
        new_state = %{socket: socket, ftp_data_pid: ftp_data_pid, aborted: true, server_name: server_name}
        {:reply, state, new_state}
    end

    def handle_cast({:stor, to_path} , state=%{socket: socket, ftp_data_pid: ftp_data_pid, aborted: aborted, server_name: server_name}) do
        logger_debug "Receiving file..."
        {:ok, file} = receive_file(socket)
        logger_debug("This is packet: #{inspect file}")
        file_size = byte_size(file)
        logger_debug("This is size: #{inspect file_size}")
        :file.write_file(to_charlist(to_path), file)
        logger_debug "File received."
        message_ftp_data(:socket_transfer_ok)
        message_ftp_data(:close_pasv_socket)
        {:noreply, state}
    end

    def handle_cast({:retr, file, new_offset} , state) do
        file_info = transfer_info(file, 512, new_offset)
        logger_debug "Sending file (#{inspect file_info})..."
        Map.get(state, :socket) |> send_file(file, file_info, new_offset, 512, 1)
        {:noreply, state}
    end


    def handle_info({:send, {socket, file, file_info, new_offset, bytes, transmission_number}}, state) do
        aborted = Map.get(state, :aborted)
        case aborted do
          false ->
            send_file(socket, file, file_info, new_offset, bytes, transmission_number)
          true ->
            logger_debug "Aborting this transfer"
            message_ftp_data(:socket_transfer_failed)
        end
        ftp_data_pid =  Process.get(:ftp_data_pid)
        {:noreply, state}
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
            message_ftp_data(:close_pasv_socket)
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
          {:ok, _exit_code} -> :chunk_sent
          {:error, _reason} -> :chunk_not_sent
        end
      end


    def handle_cast({:list, file_info} , state) do
        logger_debug "Sending result from LIST command... -- #{inspect state}"
        Map.get(state, :socket) |> :gen_tcp.send(file_info)
        logger_debug "Result from LIST command sent. Sent #{inspect file_info}"
        message_ftp_data(:socket_transfer_ok)
        message_ftp_data(:close_pasv_socket)
        {:noreply, state}
    end


    defp message_ftp_data(message) do
        pid = Process.get(:ftp_data_pid)
        Kernel.send(pid, {:from_pasv_socket, message})
    end

    defp logger_debug(message) do
        pid = Process.get(:ftp_data_pid)
        Kernel.send(pid, {:ftp_pasv_log_message, message})
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

end