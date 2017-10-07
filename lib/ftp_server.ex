defmodule FtpServer do
    @moduledoc """
    Documentation for FtpServer
    """
    @ftp_DATACONN            150
    @ftp_OK                  200
    @ftp_NOOPOK              200
    @ftp_TYPEOK              200
    @ftp_PORTOK              200
    @ftp_STRUOK              200
    @ftp_MODEOK              200
    @ftp_ALLOOK              202
    @ftp_NOFEAT              211
    @ftp_STATOK              211
    @ftp_STATFILE_OK         213
    @ftp_HELP                214
    @ftp_SYSTOK              215
    @ftp_GREET               220
    @ftp_GOODBYE             221
    @ftp_TRANSFEROK          226
    @ftp_ABORTOK             226
    @ftp_PASVOK              227
    @ftp_EPRTOK              228
    @ftp_EPSVOK              229
    @ftp_LOGINOK             230
    @ftp_CWDOK               250
    @ftp_RMDIROK             250
    @ftp_DELEOK              250
    @ftp_RENAMEOK            250
    @ftp_PWDOK               257
    @ftp_MKDIROK             257
    @ftp_GIVEPWORD           331
    @ftp_RESTOK              350
    @ftp_RNFROK              350
    @ftp_TIMEOUT             421
    @ftp_ABORT               421
    @ftp_BADUSER_PASS        430
    @ftp_BADSENDCONN         425
    @ftp_BADSENDNET          426
    @ftp_BADSENDFILE         451
    @ftp_BADCMD              500
    @ftp_COMMANDNOTIMPL      502
    @ftp_NEEDUSER            503
    @ftp_NEEDRNFR            503
    @ftp_BADSTRU             504
    @ftp_BADMODE             504
    @ftp_LOGINERR            530
    @ftp_FILEFAIL            550
    @ftp_NOPERM              550
    @ftp_UPLOADFAIL          553

    @timeout :infinity
    @server_name __MODULE__
    @debug 2
    @restart_time 5000
    require Logger
    use GenServer

    def start_link(args = %{ftp_data_pid: ftp_data_pid, ftp_info_pid: ftp_info_pid, root_dir: root_dir, username: username, password: password, ip: ip, port: port}) do
        initial_state = %{root_dir: root_dir, ftp_data_pid: ftp_data_pid, ftp_info_pid: ftp_info_pid, socket: nil, username: username, password: password, ip: ip, port: port}
        GenServer.start_link(__MODULE__, initial_state, name: @server_name)
    end

    def init(state= %{root_dir: root_dir, ftp_data_pid: ftp_data_pid, ftp_info_pid: ftp_info_pid, socket: socket, username: username, password: password, ip: ip, port: port}) do
        FtpData.get_state ftp_data_pid
        FtpData.set_server_pid(ftp_data_pid, self())
        start_listener(state)
        {:ok, state}
    end

    def set_state(state) do
        GenServer.call __MODULE__, {:set_state, state}
    end

    def handle_call({:set_state, new_state}, _from, state) do
        {:reply, state, new_state}
    end

    def handle_info(:listen, state=%{root_dir: root_dir, ftp_data_pid: ftp_data_pid, ftp_info_pid: ftp_info_pid, socket: old_socket, username: username, password: password, ip: ip, port: port}) do
        logger_debug "Listening..."
        {:ok, lsocket} = :gen_tcp.listen(port, [ip: ip, active: false, backlog: 1024, nodelay: true, send_timeout: 30000, send_timeout_close: true])

        new_state =
        case :gen_tcp.accept(lsocket) do
            {:ok, socket} ->
                new_state=%{root_dir: root_dir, ftp_data_pid: ftp_data_pid, ftp_info_pid: ftp_info_pid, socket: socket, username: username, password: password, ip: ip, port: port}
                Kernel.send(ftp_info_pid, {:set_server_state, new_state} )
                logger_debug "got connection"
                send_message(@ftp_OK, "Welcome to FTP Server", socket, false)
                sucessful_authentication = auth(socket, "user1", "user1")
                case sucessful_authentication do
                    true ->
                        send_message(@ftp_LOGINOK, "User Authenticated", socket, false)
                        case :inet.setopts(socket, [active: true]) do
                            :ok -> logger_debug "Socket successfully set to active"
                            {:error, reason} -> logger_debug "Socket not set to active. Reason #{reason}"
                        end
                        %{root_dir: root_dir, ftp_data_pid: ftp_data_pid, ftp_info_pid: ftp_info_pid, socket: nil}
                    false ->
                        logger_debug("Invalid username or password\n")
                        send_message(@ftp_LOGINERR, "Invalid username or password", socket, false)
                        new_state=%{root_dir: root_dir, ftp_data_pid: ftp_data_pid, ftp_info_pid: ftp_info_pid, socket: nil, username: username, password: password, ip: ip, port: port}
                        Kernel.send(ftp_info_pid, {:set_server_state, new_state} )
                        :gen_tcp.close(socket)
                        :gen_tcp.close(lsocket)
                        logger_debug("Restarting Server in #{inspect @restart_time} ms...\n")
                        :timer.sleep(5000) ## allow time for sockets to close properly.
                        start_listener(new_state)
                end

            {:error, reason} -> logger_debug "Got error while listening #{reason}"
        end

        {:noreply, state}
    end

    def handle_info({:get_command, socket}, state) do
        logger_debug "Waiting for command on socket #{inspect socket}..."
        case :gen_tcp.recv(socket, 0) do
            {:ok, packet} ->
                logger_debug "got command: #{packet}"
                handle_command(packet, socket, state)
            {:error, reason} -> logger_debug "Got error while waiting #{reason}"
        end
        {:noreply, state}
    end

    def handle_info({:from_data_socket, msg},state) do
        socket = Map.get(state, :socket)
        logger_debug "This is msg: #{inspect msg}"
        x = case msg do
            :socket_transfer_ok -> send_message(@ftp_TRANSFEROK, "Transfer Complete", socket)
            :socket_transfer_failed -> send_message(@ftp_FILEFAIL, "Transfer Failed", socket)
            :socket_close_ok -> 1#send_message(@ftp_TRANSFEROK, "Transfer Complete", socket)
            :socket_create_ok -> 2#send_message(@ftp_TRANSFEROK, "Transfer Complete", socket)
            _ -> :ok
        end
        {:noreply, state}
    end

    def handle_info({:tcp, pid, packet }, state) do
        socket = Map.get(state, :socket)
        logger_debug "got command: #{packet}"
        handle_command(packet, socket, state)
        {:noreply, state}
    end

    def handle_info({:tcp_closed, socket }, state) do
        logger_debug "Socket #{inspect socket} closed."
        #start_listener(state) # restart socket again to be ready for a new connection
        {:noreply, state}
    end
    
    def terminate(_reason, state=%{root_dir: root_dir, ftp_data_pid: ftp_data_pid, ftp_info_pid: ftp_info_pid, socket: socket, username: username, password: password, ip: ip, port: port}) do
        Logger.info "This is terminiate reason: #{inspect _reason}"
        :gen_tcp.close(socket)
    end

    def handle_command(command, socket, state) do
        logger_debug("FROM CLIENT: #{command}")
        #buffer2 = Enum.join([buffer, command])
        command = to_string(command)
        {code, response} =
        cond do
            String.contains?(command, "LIST") == true -> handle_list(socket, command, state)
            String.contains?(command, "TYPE") == true -> handle_type(socket, command, state)
            String.contains?(command, "STRU") == true -> handle_stru(socket, command, state)
            # String.contains?(command, "USER") == true -> handle_user(socket, command, state)
            String.contains?(command, "QUIT") == true -> handle_quit(socket, command, state)
            String.contains?(command, "PORT") == true -> handle_port(socket, command, state)
            String.contains?(command, "RETR") == true -> handle_retr(socket, command, state)
            String.contains?(command, "STOR") == true -> handle_stor(socket, command, state)
            String.contains?(command, "NOOP") == true -> handle_noop(socket, command, state)
            # String.contains?(command, "DELE") == true -> handle_dele(socket, command, state)
            # String.contains?(command, "MKD") == true -> handle_mkd(socket, command, state)
            # String.contains?(command, "RMD") == true -> handle_rmd(socket, command, state)
            String.contains?(command, "SIZE") == true -> handle_size(socket, command, state)
            String.contains?(command, "PASV") == true -> handle_pasv(socket, command, state)
            String.contains?(command, "SYST") == true -> handle_syst(socket, command, state)
            String.contains?(command, "FEAT") == true -> handle_feat(socket, command, state)
            String.contains?(command, "PWD") == true -> handle_pwd(socket, command, state)
            String.contains?(command, "CWD") == true -> handle_cwd(socket, command, state)
            String.contains?(command, "REST") == true -> handle_rest(socket, command, state)
            String.contains?(command, "MODE") == true -> handle_mode(socket, command, state)
            String.contains?(command, "ABOR") == true -> handle_abor(socket, command, state)
            true -> {@ftp_COMMANDNOTIMPL, "Command not implemented on this server"}
        end

        case code do
            0 -> :ok
            _ -> send_message(code, response, socket)
        end
    end

    def start_listener(state=%{root_dir: root_dir, ftp_data_pid: ftp_data_pid, ftp_info_pid: ftp_info_pid, socket: socket, username: username, password: password, ip: ip, port: port}) do
        Kernel.send(self(), :listen)
    end


    def get_state() do
        GenServer.call __MODULE__, :get_state
    end

    def handle_call(:get_state, _from, state) do
        {:reply, state, state}
    end


      ## COMMAND HANDLERS

    def handle_noop(socket, command, state) do
        {@ftp_NOOPOK, "No Operation"}
    end

    def handle_feat(socket, command, state) do
        {@ftp_NOFEAT, "no-features"}
    end

    def handle_pasv(socket, command, state) do
        {@ftp_PASVOK, "Entering Passive Mode"}
    end

    def handle_abor(socket, command, state) do
        pid = Map.get(state, :ftp_data_pid)
        FtpData.close_socket pid
        {@ftp_ABORTOK, "Abort Command Successful"}
    end

    def handle_type(socket, command, state) do
        "TYPE " <> type = command |> String.trim()
        case type do
            "I" -> {@ftp_TYPEOK, "Image"}
            "A" -> {@ftp_TYPEOK, "ASCII"}
            "E" -> {@ftp_TYPEOK, "EBCDIC"}
            _ -> {@ftp_TYPEOK, "ASCII Non-print"}
        end
    end

    def handle_rest(socket, command, state) do
        "REST " <> offset = command |> String.trim()
        update_file_offset(String.to_integer(offset), state)
        {@ftp_RESTOK, "Rest Supported. Offset set to #{offset}"}
    end

    def handle_syst(socket, command, state) do
        {@ftp_SYSTOK, "UNIX Type: L8"}
    end

    def handle_stru(socket, command, state) do
        {@ftp_STRUOK, "FILE"}
    end

    def handle_quit(socket, command, state) do
        {@ftp_GOODBYE, "Goodbye"}
    end

    def handle_mode(socket, command, state) do
        "MODE " <> mode = command |> String.trim()
        case mode do
            "C" -> {@ftp_MODEOK, "Compressed"}
            "B" -> {@ftp_MODEOK, "Block"}
            _ -> {@ftp_MODEOK, "Stream"}
        end
    end

    def handle_port(socket, command, state) do
        "PORT " <> port_data = command |> String.trim()
        [ h1, h2, h3, h4, p1, p2] = String.split(port_data, ",")
        port_number = String.to_integer(p1)*256 + String.to_integer(p2)
        port = to_string(port_number)
        ip = Enum.join([h1, h2, h3, h4], ".")
        update_data_socket_info(ip, port_number, state)
        {@ftp_PORTOK, "Client IP: #{ip}. Client Port: #{port}"}
    end

    def handle_list(socket, command, state) do
        ftp_info_pid = Map.get(state, :ftp_info_pid)
        ftp_data_pid = Map.get(state, :ftp_data_pid)
        case command do
            "LIST\r\n" ->
                %{root_dir: root_dir, server_cd: current_server_working_directory , client_cd: current_client_working_directory, data_ip: ip, data_port: port, type: type, offset: offset} = FtpInfo.get_state ftp_info_pid
                {:ok, files} = File.ls(current_server_working_directory)
                file_info = get_info(current_server_working_directory, files, state)
                file_info = Enum.join([file_info, "\r\n"])
                send_message(@ftp_DATACONN, "Opening Data Socket for transfer of ls command...", socket)
                ip = to_charlist(ip)
                FtpData.create_socket(ftp_data_pid, ip, port)
                FtpData.list(ftp_data_pid, file_info)
                {0, :ok}
            "LIST -a\r\n" ->
                %{root_dir: root_dir, server_cd: current_server_working_directory , client_cd: current_client_working_directory, data_ip: ip, data_port: port, type: type, offset: offset} = FtpInfo.get_state ftp_info_pid
                {:ok, files} = File.ls(current_server_working_directory)
                file_info = get_info(current_server_working_directory, files, state)
                file_info = Enum.join([file_info, "\r\n"])
                send_message(@ftp_DATACONN, "Opening Data Socket for transfer of ls command...", socket)
                ip = to_charlist(ip)
                FtpData.create_socket(ftp_data_pid, ip, port)
                FtpData.list(ftp_data_pid, file_info)
                {0, :ok}
            _ -> {@ftp_COMMANDNOTIMPL, "Command not implemented on this server"}


        end
    end

    def handle_size(socket, command, state) do
        "SIZE " <> path = command |> String.trim()
        ftp_info_pid = Map.get(state, :ftp_info_pid)
        %{root_dir: root_dir, server_cd: current_server_working_directory , client_cd: current_client_working_directory, data_ip: ip, data_port: port, type: type, offset: offset} = FtpInfo.get_state ftp_info_pid
        working_path = determine_path(root_dir, current_client_working_directory, path)

        path_exists = File.exists?(working_path)
        is_directory = File.dir?(working_path)
        have_read_access = allowed_to_read(working_path, state)

        cond do
            is_directory == true -> {@ftp_FILEFAIL, "Current path '#{path}' is a directory."}
            path_exists == false -> {@ftp_FILEFAIL, "Current directory '#{path}' does not exist."}
            have_read_access == false -> {@ftp_NOPERM, "You don't have permission to read from this directory ('#{path}')."}
            true ->
                {:ok, info} = File.stat(working_path)
                file_size = Map.get(info, :size)
                {@ftp_STATFILE_OK, "#{file_size}"}
        end
    end

    def handle_stor(socket, command, state) do
        ftp_info_pid = Map.get(state, :ftp_info_pid)
        ftp_data_pid = Map.get(state, :ftp_data_pid)
        "STOR " <> path = command |> String.trim()
        %{root_dir: root_dir, server_cd: current_server_working_directory , client_cd: current_client_working_directory, data_ip: ip, data_port: port, type: type, offset: offset} = FtpInfo.get_state ftp_info_pid
        working_path = determine_path(root_dir, current_client_working_directory, path)

        case allowed_to_write(working_path) do
            true ->
                logger_debug "working_dir: #{working_path}"
                case File.exists?(working_path) do
                    true -> File.rm(working_path)
                    false -> :ok
                end
                send_message(@ftp_DATACONN, "Opening Data Socket to receive file...", socket)
                ip = to_charlist(ip)
                FtpData.create_socket(ftp_data_pid, ip, port)
                FtpData.stor(ftp_data_pid, working_path)
                {0, :ok}
            false ->
                {@ftp_NOPERM, "You don't have permission to write to this directory ('#{path}')."}
        end
    end

    def handle_retr(socket, command, state) do
        "RETR " <> path = command |> String.trim()
        ftp_info_pid = Map.get(state, :ftp_info_pid)
        ftp_data_pid = Map.get(state, :ftp_data_pid)
        %{root_dir: root_dir, server_cd: current_server_working_directory , client_cd: current_client_working_directory, data_ip: ip, data_port: port, type: type, offset: offset} = FtpInfo.get_state ftp_info_pid
        working_path = determine_path(root_dir, current_client_working_directory, path)

        path_exists = File.exists?(working_path)
        is_directory = File.dir?(working_path)
        have_read_access = allowed_to_read(working_path, state)

        cond do
            is_directory == true -> {@ftp_FILEFAIL, "Current path '#{path}' is a directory."}
            path_exists == false -> {@ftp_FILEFAIL, "Current directory '#{path}' does not exist."}
            have_read_access == false -> {@ftp_NOPERM, "You don't have permission to read from this directory ('#{path}')."}
            true ->
                send_message(@ftp_DATACONN, "Opening Data Socket for transfer of file #{path} from offset #{offset}...", socket)
                ip = to_charlist(ip)
                FtpData.create_socket(ftp_data_pid, ip, port)
                FtpData.retr(ftp_data_pid, working_path, offset)
                {0, :ok}
        end
    end

    def handle_pwd(socket, command, state) do
        ftp_info_pid = Map.get(state, :ftp_info_pid)
        state = FtpInfo.get_state ftp_info_pid
        working_directory =  Map.get(state, :client_cd)
        {@ftp_PWDOK, "\"#{working_directory}\""}
    end

    def handle_cwd(socket, command, state) do
        ftp_info_pid = Map.get(state, :ftp_info_pid)
        "CWD " <> path = command |> String.trim()

        current_client_working_directory = FtpInfo.get_state(ftp_info_pid) |> Map.get(:client_cd)
        root_directory = FtpInfo.get_state(ftp_info_pid) |> Map.get(:root_dir)
        path = determine_path(root_directory, current_client_working_directory, path)
        logger_debug "This is working path on server: #{path}"
        new_client_working_directory = String.trim_leading(path, root_directory)
        
        path_exists = File.exists?(path)
        is_directory = File.dir?(path)
        have_read_access = allowed_to_read(path, state)

        cond do
            is_directory == false -> {@ftp_FILEFAIL, "Current path '#{new_client_working_directory}' is not a directory."}
            path_exists == false -> {@ftp_FILEFAIL, "Current directory '#{new_client_working_directory}' does not exist."}
            have_read_access == false -> {@ftp_NOPERM, "You don't have permission to read from this directory ('#{new_client_working_directory}')."}
            true ->
                update_client_cd(new_client_working_directory, state)
                update_server_cd(path, state)
                {@ftp_CWDOK, "Current directory changed to '#{new_client_working_directory}'"}
        end
    end


    ## HELPER FUNCTIONS


    defp valid_username(expected_username, username) do
        case (expected_username == username) do
            true -> 0
            false -> 1
        end
    end

    defp valid_password(expected_password, password) do
        case (expected_password == password) do
            true -> 0
            false -> 1
        end
    end

    defp logger_debug(message, id \\ "") do
        case @debug do
            0 -> :ok
            _ -> Logger.debug(message)
        end
    end

    defp send_message(code, msg, socket, socket_mode \\ true) do
        message = Enum.join([to_string(code), " " , msg, "\r\n"])
        case @debug do
            2 ->
                logger_debug("Sending this message to client: #{message}. Socket = #{inspect socket}")
            _ -> :ok
        end

        ## temporarily set to false so we can send messages
        :inet.setopts(socket, [active: false])

        case :inet.getopts(socket, [:active]) do
            {:ok, opts} -> logger_debug "This is socket now: #{inspect opts}"
            {:error, reason} -> logger_debug "Error getting opts. Reason #{reason}"
        end

        send_status =
        case :gen_tcp.send(socket, message) do
            :ok -> "Message '#{message}'' sent to client"
            {:error, reason} -> "Error sending message to Client: #{reason}"
        end

        case @debug do
            2 ->
                logger_debug("FROM SERVER #{message}")
                logger_debug(send_status)
            _ -> :ok
        end
        
        :inet.setopts(socket, [active: socket_mode])

        case :inet.getopts(socket, [:active]) do
            {:ok, opts} -> logger_debug "This is socket now: #{inspect opts}"
            {:error, reason} -> logger_debug "Error getting opts. Reason #{reason}"
        end
    end

    defp is_absolute_path(path) do
        case ( path == String.trim_leading(path, "/") ) do
            true -> false
            false -> true
        end
    end

    defp update_client_cd(new_client_dir, state) do
        ftp_info_pid = Map.get(state, :ftp_info_pid)
        %{root_dir: root_dir, server_cd: server_cd , client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset} = FtpInfo.get_state ftp_info_pid
        new_state = %{root_dir: root_dir, server_cd: server_cd ,client_cd: new_client_dir, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset }
        FtpInfo.set_state(ftp_info_pid, new_state)
    end

    defp update_server_cd(new_server_dir, state) do
        ftp_info_pid = Map.get(state, :ftp_info_pid)
        %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset} = FtpInfo.get_state ftp_info_pid
        new_state = %{root_dir: root_dir, server_cd: new_server_dir ,client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset }
        FtpInfo.set_state(ftp_info_pid, new_state)
    end

    defp update_file_offset(new_offset, state) do
        ftp_info_pid = Map.get(state, :ftp_info_pid)
        %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset} = FtpInfo.get_state ftp_info_pid
        new_state = %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: new_offset }
        FtpInfo.set_state(ftp_info_pid, new_state)
    end

    defp update_data_socket(new_data_socket, state) do
        ftp_info_pid = Map.get(state, :ftp_info_pid)
        %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset} = FtpInfo.get_state ftp_info_pid
        new_state = %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: new_data_socket, data_ip: ip, data_port: port, type: type, offset: offset }
        FtpInfo.set_state(ftp_info_pid, new_state)
    end

    defp update_data_socket_info(new_ip, new_port, state) do
        ftp_info_pid = Map.get(state, :ftp_info_pid)
        %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset} = FtpInfo.get_state ftp_info_pid
        new_state = %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: data_socket, data_ip: new_ip, data_port: new_port, type: type, offset: offset }
        FtpInfo.set_state(ftp_info_pid, new_state)
    end

    defp reset_data_socket(state) do
        update_data_socket(nil, state)
        update_data_socket_info(nil, nil, state)
        update_file_offset(0, state)
    end

    @doc """
    Simple module to check if the user can view a file/folder. Function attempts to
    perform a `String.trim_leading` call on the `current_path`. If `current_path` is
    part of the `root_path`, the `String.trim_leading` call will be able to remove the
    `root_path` string from the `current_path` string. If not, it will simply return
    the original `current_path`
    """
    defp allowed_to_read(current_path, state) do
        ftp_info_pid = Map.get(state, :ftp_info_pid)
        info_state = FtpInfo.get_state ftp_info_pid
        Logger.info "This is info_state: #{inspect info_state}"
        root_dir = Map.get(info_state, :root_dir)
        case (current_path == root_dir) do
        true ->
            true
        false ->
            case (current_path == String.trim_leading(current_path, root_dir)) do
            true ->
                false
            false ->
                true
            end
        end

        true
    end

    defp allowed_to_write(current_path) do
        true
    end

    def get_info(cd,files, state) do
        list = for file <- files, do: Enum.join([cd, "/", file]) |> format_file_info(state)
        Enum.join(list, "\r\n")
    end

    def format_file_info(file, state) do
        ftp_info_pid = Map.get(state, :ftp_info_pid)
        state = FtpInfo.get_state ftp_info_pid
        root_dir = Map.get(state, :root_dir)
        name = String.trim_leading(file, root_dir) |> String.split("/") |> List.last
        logger_debug "getting info for #{file}"
        {:ok, info} = File.stat(file)
        size = Map.get(info, :size)
        {{y, m, d}, {h, min, s}} = Map.get(info, :mtime)
        time = Enum.join([h, min], ":")
        m = format_month(m)
        timestamp = Enum.join([m, d, time], " ")
        links = Map.get(info, :links)
        uid = Map.get(info, :uid)
        gid = Map.get(info, :gid)
        type = Map.get(info, :type)
        access = Map.get(info, :access)
        permissions = format_permissions(type, access)
        Enum.join([permissions, links, uid, gid, size, timestamp, name], " ")
    end

    def format_permissions(type, access) do
        directory =
        case type do
            :directory -> "d"
            _ -> "-"
        end
        permissions =
        case access do
            :read -> "r--"
            :write -> "w--"
            :read_write -> "rw-"
            :none -> "---"
        end
        Enum.join([directory, permissions, permissions, permissions])
    end

    def format_month(month) do
        cond do
            month == 1 -> "Jan"
            month == 2 -> "Feb"
            month == 3 -> "Mar"
            month == 4 -> "Apr"
            month == 5 -> "May"
            month == 6 -> "Jun"
            month == 7 -> "Jul"
            month == 8 -> "Aug"
            month == 9 -> "Sep"
            month == 10 -> "Oct"
            month == 11 -> "Nov"
            month == 12 -> "Dec"
        end
    end

    defp auth(socket, expected_username, expected_password) do
        {:ok, data} = :gen_tcp.recv(socket, 0)
        logger_debug "Username Given: #{inspect data}"
        "USER " <> username = to_string(data) |> String.trim()

        send_message(@ftp_GIVEPWORD,"Enter Password", socket, false)
        {:ok, data} = :gen_tcp.recv(socket, 0)
        logger_debug "Password Given: #{inspect data}"
        "PASS " <> password = to_string(data) |> String.trim()

        valid_credentials = valid_username(expected_username, username) + valid_password(expected_password, password)
        case valid_credentials do
            0 -> true
            _ -> false
        end
    end

    defp determine_path(root_dir, cd, path) do
        ## check if path given is an absolute path
        new_path = 
        case is_absolute_path(path) do
            true -> String.trim_leading(path, "/") |> Path.expand(root_dir)
            false -> String.trim_leading(path, "/") |> Path.expand(cd) |> String.trim_leading("/") |> Path.expand(root_dir)
        end
        logger_debug "This is the path we were given: '#{path}'. This is cd: '#{cd}'. This is root_dir: '#{root_dir}'. Determined that this is the current path: '#{new_path}'"
        new_path
    end
end
