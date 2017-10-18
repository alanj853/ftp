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
    @ftp_TRANSFERABORTED     426
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
    @restart_time 500
    require Logger
    use GenServer

    def start_link(ref, socket, transport, opts = [%{ftp_logger_pid: ftp_logger_pid, ftp_data_pid: ftp_data_pid, root_dir: root_dir, username: username, password: password, ip: ip, port: port, debug: debug, timeout: timeout, restart_time: restart_time}]) do
        initial_state = %{ftp_logger_pid: ftp_logger_pid, ftp_data_pid: ftp_data_pid, root_dir: root_dir, username: username, password: password, ip: ip, port: port, debug: debug, timeout: timeout, restart_time: restart_time, listener_ref: ref, control_socket: socket, transport: transport}
        pid  = :proc_lib.spawn_link(__MODULE__, :init, [ref, socket, transport, initial_state])
        {:ok, pid}
    end

    def init(ref, socket, transport, state) do
        start_listener(ref,socket, state)
        :gen_server.enter_loop(__MODULE__, [], [])
        {:ok, %{}}
    end   
    
    defp start_listener(listener_pid, socket, state) do
        setup_dd(state)
        FtpData.set_server_pid(get(:ftp_data_pid), self())
        :ranch.accept_ack(listener_pid)
        socket_status = Port.info(socket)
        logger_debug "Got Connection. Socket status: #{inspect socket_status}"
        send_message(@ftp_OK, "Welcome to FTP Server", false)

        case :ranch_tcp.setopts(socket, [active: true]) do
            :ok -> logger_debug "Socket successfully set to active"
            {:error, reason} -> logger_debug "Socket not set to active. Reason #{reason}"
        end
        
        sucessful_authentication = auth(socket)
        case sucessful_authentication do
            true ->
                logger_debug "Valid Login Credentials"
                send_message(@ftp_LOGINOK, "User Authenticated")
            false ->
                logger_debug("Invalid username or password\n")
                send_message(@ftp_LOGINERR, "Invalid username or password")
                #close_socket(socket)
        end
    end

    def set_state(state) do
        GenServer.call __MODULE__, {:set_state, state}
    end

    def get_state() do
        GenServer.call self(), :get_state
    end

    def handle_call({:set_state, new_state}, _from, state) do
        {:reply, state, new_state}
    end

    def handle_call(:get_state, _from, state) do
        socket_status = Map.get(state, :socket) |> Port.info
        logger_debug "Got state. Socket status: #{inspect socket_status}"
        {:reply, state, state}
    end

    def handle_info({:ftp_data_log_message, message}, state) do
        Enum.join([" [FTP_DATA]   ", message]) |> logger_debug
        {:noreply, state}
    end

    def handle_info({:from_ftp_data, msg},state) do
        socket = get(:control_socket)
        ftp_data_pid = get(:ftp_data_pid)
        logger_debug "This is msg: #{inspect msg}"
        case msg do
            :socket_transfer_ok -> send_message(@ftp_TRANSFEROK, "Transfer Complete")
            :socket_transfer_failed -> 
                was_aborted = FtpData.get_state(ftp_data_pid) |> Map.get(:aborted)
                case was_aborted do
                    true -> #:ok
                        send_message(@ftp_TRANSFERABORTED, "Connection closed; transfer aborted.")
                        send_message(@ftp_ABORTOK, "ABOR command successful")
                    false -> send_message(@ftp_FILEFAIL, "Transfer Failed")
                end
            :socket_close_ok -> 1#send_message(@ftp_TRANSFEROK, "Transfer Complete", socket)
            :socket_create_ok -> 2#send_message(@ftp_TRANSFEROK, "Transfer Complete", socket)
            _ -> :ok
        end
        {:noreply, state}
    end

    def handle_info({:tcp, socket, packet }, state) do
        control_socket = get(:control_socket)
        data_socket = get(:data_socket)
        cond do
            (socket == control_socket) -> 
                logger_debug "got command: #{packet}"
                handle_command(packet)
            (socket == data_socket ) ->
                logger_debug "got command for data socket: #{packet}"
            true ->
                logger_debug "got command from other socket #{socket}"
        end
        {:noreply, state}
    end

    def handle_info({:tcp_closed, socket }, state) do
        socket_status = Port.info(socket)
        logger_debug "Socket #{inspect socket} closed. Actual Socket status: #{inspect socket_status} . Connection to client ended"
        {:noreply, state}
    end
    
    def terminate(reason, state) do
        logger_debug "This is terminiate reason:\nSTART\n#{inspect reason}\nEND"
        #close_socket(socket) # make sure socket is closed
        #close_socket(listen_socket)
    end

    def terminate({:timeout, _}, state) do
        logger_debug "Terminating from timeout"
        #close_socket(socket) # make sure socket is closed
        #close_socket(listen_socket)
    end


      ## COMMAND HANDLERS

    defp handle_command(command) do
        logger_debug("FROM CLIENT: #{command}")
        #buffer2 = Enum.join([buffer, command])
        socket = get(:control_socket)
        command = to_string(command)
        {code, response} =
        cond do
            String.contains?(command, "LIST") == true -> handle_list(command)
            String.contains?(command, "TYPE") == true -> handle_type(command)
            String.contains?(command, "STRU") == true -> handle_stru(command)
            String.contains?(command, "QUIT") == true -> handle_quit(command)
            String.contains?(command, "PORT") == true -> handle_port(command)
            String.contains?(command, "RETR") == true -> handle_retr(command)
            String.contains?(command, "STOR") == true -> handle_stor(command)
            String.contains?(command, "NOOP") == true -> handle_noop(command)
            String.contains?(command, "DELE") == true -> handle_dele(command)
            String.contains?(command, "MKD") == true -> handle_mkd(command)
            String.contains?(command, "RMD") == true -> handle_rmd(command)
            String.contains?(command, "SIZE") == true -> handle_size(command)
            String.contains?(command, "PASV") == true -> handle_pasv(command)
            String.contains?(command, "SYST") == true -> handle_syst(command)
            String.contains?(command, "FEAT") == true -> handle_feat(command)
            String.contains?(command, "PWD") == true -> handle_pwd(command)
            String.contains?(command, "CWD") == true -> handle_cwd(command)
            String.contains?(command, "REST") == true -> handle_rest(command)
            String.contains?(command, "MODE") == true -> handle_mode(command)
            String.contains?(command, "ABOR") == true -> handle_abor(command)
            true -> {@ftp_COMMANDNOTIMPL, "Command not implemented on this server"}
        end

        case code do
            0 -> :ok
            _ -> send_message(code, response)
        end
    end

    def handle_dele(command) do
        ftp_data_pid = get(:ftp_data_pid)
        "DELE " <> path = command |> String.trim()
        root_dir = get(:root_dir)
        current_client_working_directory = get(:client_cd)
        working_path = determine_path(root_dir, current_client_working_directory, path)
        path_exists = File.exists?(working_path)
        is_directory = File.dir?(working_path)
        have_read_access = allowed_to_read(working_path)

        cond do
            is_directory == true -> {@ftp_FILEFAIL, "Current path '#{path}' is a directory."}
            path_exists == false -> {@ftp_FILEFAIL, "Current directory '#{path}' does not exist."}
            have_read_access == false -> {@ftp_NOPERM, "You don't have permission to delete this file ('#{path}')."}
            true ->
                File.rm(working_path)
                {@ftp_DELEOK, "Successfully deleted file '#{path}'"}
        end
    end

    def handle_rmd(command) do
        ftp_data_pid = get(:ftp_data_pid)
        "RMD " <> path = command |> String.trim()
        root_dir = get(:root_dir)
        current_client_working_directory = get(:client_cd)
        working_path = determine_path(root_dir, current_client_working_directory, path)
        path_exists = File.exists?(working_path)
        is_directory = File.dir?(working_path)
        have_read_access = allowed_to_read(working_path)

        cond do
            is_directory == false -> {@ftp_FILEFAIL, "Current path '#{path}' is not a directory."}
            path_exists == false -> {@ftp_FILEFAIL, "Current directory '#{path}' does not exist."}
            have_read_access == false -> {@ftp_NOPERM, "You don't have permission to delete this file ('#{path}')."}
            true ->
                File.rmdir(working_path)
                {@ftp_RMDIROK, "Successfully deleted directory '#{path}'"}
        end
    end

    def handle_mkd(command) do
        ftp_data_pid = get(:ftp_data_pid)
        "MKD " <> path = command |> String.trim()
        root_dir = get(:root_dir)
        current_client_working_directory = get(:client_cd)
        working_path = determine_path(root_dir, current_client_working_directory, path)
        path_exists = File.exists?(working_path)
        have_read_access = allowed_to_read(working_path)

        cond do
            path_exists == true -> {@ftp_FILEFAIL, "Current directory '#{path}' already exists."}
            have_read_access == false -> {@ftp_NOPERM, "You don't have permission to create this directory ('#{path}')."}
            true ->
                File.mkdir(working_path)
                {@ftp_MKDIROK, "Successfully created directory '#{path}'"}
        end
    end

    def handle_noop(command) do
        {@ftp_NOOPOK, "No Operation"}
    end

    def handle_feat(command) do
        {@ftp_NOFEAT, "no-features"}
    end

    def handle_pasv(command) do
        ftp_data_pid = get(:ftp_data_pid)
        p1 = 100 # :random.uniform(250)
        p2 = 150 #:random.uniform(250)
        port_number = p1*256 + p2
        ip = get(:control_ip)
        {h1, h2, h3, h4} = ip
        FtpData.pasv(ftp_data_pid, ip, port_number)
        logger_debug "This is control ip: #{inspect ip}"
        {@ftp_PASVOK, "Entering Passive Mode (#{inspect h1},#{inspect h2},#{inspect h3},#{inspect h4},#{inspect p1},#{inspect p2})."}
    end

    def handle_abor(command) do
        logger_debug "Handling abort.."
        pid = get(:ftp_data_pid)
        FtpData.close_data_socket(pid, :abort)
        {0, :ok}
        #send_message(@ftp_TRANSFERABORTED, "Connection closed; transfer aborted.")
        #send_message(@ftp_ABORTOK, "ABOR command successful")
        #{@ftp_ABORTOK, "Abort Command Successful"}
    end

    def handle_type(command) do
        "TYPE " <> type = command |> String.trim()
        case type do
            "I" -> {@ftp_TYPEOK, "Image"}
            "A" -> {@ftp_TYPEOK, "ASCII"}
            "E" -> {@ftp_TYPEOK, "EBCDIC"}
            _ -> {@ftp_TYPEOK, "ASCII Non-print"}
        end
    end

    def handle_rest(command) do
        "REST " <> offset = command |> String.trim()
        update_file_offset(String.to_integer(offset))
        {@ftp_RESTOK, "Rest Supported. Offset set to #{offset}"}
    end

    def handle_syst(command) do
        {@ftp_SYSTOK, "UNIX Type: L8"}
    end

    def handle_stru(command) do
        {@ftp_STRUOK, "FILE"}
    end

    def handle_quit(command) do
        {@ftp_GOODBYE, "Goodbye"}
    end

    def handle_mode(command) do
        "MODE " <> mode = command |> String.trim()
        case mode do
            "C" -> {@ftp_MODEOK, "Compressed"}
            "B" -> {@ftp_MODEOK, "Block"}
            _ -> {@ftp_MODEOK, "Stream"}
        end
    end

    def handle_port(command) do
        "PORT " <> port_data = command |> String.trim()
        [ h1, h2, h3, h4, p1, p2] = String.split(port_data, ",")
        port_number = String.to_integer(p1)*256 + String.to_integer(p2)
        port = to_string(port_number)
        ip = Enum.join([h1, h2, h3, h4], ".")
        update_data_socket_info(ip, port_number)
        {@ftp_PORTOK, "Client IP: #{ip}. Client Port: #{port}"}
    end

    def handle_list(command) do
        ftp_data_pid = get(:ftp_data_pid)
        case command do
            "LIST\r\n" ->
                current_server_working_directory = get(:server_cd)
                current_client_working_directory = get(:client_cd)
                root_dir = get(:root_dir)
                {:ok, files} = File.ls(current_server_working_directory)
                file_info = get_info(current_server_working_directory, files)
                file_info = Enum.join([file_info, "\r\n"])
                send_message(@ftp_DATACONN, "Opening Data Socket for transfer of ls command...")
                ip = get(:data_ip) |> to_charlist
                port = get(:data_port)
                FtpData.create_socket(ftp_data_pid, ip, port)
                FtpData.list(ftp_data_pid, file_info)
                {0, :ok}
            "LIST -a\r\n" ->
                current_server_working_directory = get(:server_cd)
                current_client_working_directory = get(:client_cd)
                root_dir = get(:root_dir)
                {:ok, files} = File.ls(current_server_working_directory)
                file_info = get_info(current_server_working_directory, files)
                file_info = Enum.join([file_info, "\r\n"])
                send_message(@ftp_DATACONN, "Opening Data Socket for transfer of ls command...")
                ip = get(:data_ip) |> to_charlist
                port = get(:data_port)
                FtpData.create_socket(ftp_data_pid, ip, port)
                FtpData.list(ftp_data_pid, file_info)
                {0, :ok}
            _ -> {@ftp_COMMANDNOTIMPL, "Command not implemented on this server"}
        end
    end

    def handle_size(command) do
        "SIZE " <> path = command |> String.trim()
        root_dir = get(:root_dir)
        current_client_working_directory = get(:client_cd)
        working_path = determine_path(root_dir, current_client_working_directory, path)

        path_exists = File.exists?(working_path)
        is_directory = File.dir?(working_path)
        have_read_access = allowed_to_read(working_path)

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

    def handle_stor(command) do
        "STOR " <> path = command |> String.trim()

        ftp_data_pid = get(:ftp_data_pid)
        root_dir = get(:root_dir)
        current_client_working_directory = get(:client_cd)
        socket = get(:control_socket)
        ip = get(:data_ip)
        port = get(:data_port)

        working_path = determine_path(root_dir, current_client_working_directory, path)

        case allowed_to_write(working_path) do
            true ->
                logger_debug "working_dir: #{working_path}"
                case File.exists?(working_path) do
                    true -> File.rm(working_path)
                    false -> :ok
                end
                send_message(@ftp_DATACONN, "Opening Data Socket to receive file...")
                ip = to_charlist(ip)
                FtpData.create_socket(ftp_data_pid, ip, port)
                FtpData.stor(ftp_data_pid, working_path)
                {0, :ok}
            false ->
                {@ftp_NOPERM, "You don't have permission to write to this directory ('#{path}')."}
        end
    end

    def handle_retr(command) do
        "RETR " <> path = command |> String.trim()
        
        ftp_data_pid = get(:ftp_data_pid)
        root_dir = get(:root_dir)
        current_client_working_directory = get(:client_cd)
        socket = get(:control_socket)
        ip = get(:data_ip)
        port = get(:data_port)
        offset = get(:file_offset)

        working_path = determine_path(root_dir, current_client_working_directory, path)

        path_exists = File.exists?(working_path)
        is_directory = File.dir?(working_path)
        have_read_access = allowed_to_read(working_path)

        cond do
            is_directory == true -> {@ftp_FILEFAIL, "Current path '#{path}' is a directory."}
            path_exists == false -> {@ftp_FILEFAIL, "Current directory '#{path}' does not exist."}
            have_read_access == false -> {@ftp_NOPERM, "You don't have permission to read from this directory ('#{path}')."}
            true ->
                send_message(@ftp_DATACONN, "Opening Data Socket for transfer of file #{path} from offset #{offset}...")
                ip = to_charlist(ip)
                FtpData.create_socket(ftp_data_pid, ip, port)
                FtpData.retr(ftp_data_pid, working_path, offset)
                {0, :ok}
        end
    end

    def handle_pwd(command) do
        logger_debug "Server CD: #{get(:server_cd)}"
        {@ftp_PWDOK, "\"#{get(:client_cd)}\""}
    end

    def handle_cwd(command) do
        "CWD " <> path = command |> String.trim()

        current_client_working_directory = get(:client_cd)
        root_directory = get(:root_dir)

        working_path = determine_path(root_directory, current_client_working_directory, path)
        logger_debug "This is working path on server: #{working_path}"
        new_client_working_directory = String.trim_leading(working_path, root_directory)
        new_client_working_directory = 
        case new_client_working_directory do
            "" -> "/"
            _ -> new_client_working_directory
        end
        
        path_exists = File.exists?(working_path)
        is_directory = File.dir?(working_path)
        have_read_access = allowed_to_read(working_path)

        cond do
            is_directory == false -> {@ftp_FILEFAIL, "Current path '#{new_client_working_directory}' is not a directory."}
            path_exists == false -> {@ftp_FILEFAIL, "Current directory '#{new_client_working_directory}' does not exist."}
            have_read_access == false -> {@ftp_NOPERM, "You don't have permission to read from this directory ('#{new_client_working_directory}')."}
            true ->
                update_client_cd(new_client_working_directory)
                update_server_cd(working_path)
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
        message = Enum.join([" [FTP]   ", message])

        pid = get(:ftp_logger_pid)
        Kernel.send(pid, {:ftp_server_log_message, message})
    end

    defp send_message(code, msg, socket_mode \\ true) do
        socket = get(:control_socket)
        message = Enum.join([to_string(code), " " , msg, "\r\n"])
        case @debug do
            2 ->:ok #logger_debug("Sending this message to client: #{message}. Socket = #{inspect socket}")
            _ -> :ok
        end

        ## temporarily set to false so we can send messages
        :ranch_tcp.setopts(socket, [active: false])

        # case :inet.getopts(socket, [:active]) do
        #     {:ok, opts} -> logger_debug "This is socket now: #{inspect opts}"
        #     {:error, reason} -> logger_debug "Error getting opts. Reason #{reason}"
        # end

        send_status =
        case :ranch_tcp.send(socket, message) do
            :ok -> "Message '#{message}' sent to client"
            {:error, reason} -> "Error sending message to Client: #{reason}"
        end

        case @debug do
            2 ->
                logger_debug("FROM SERVER #{message}")
                logger_debug(send_status)
            _ -> :ok
        end
        
        :ranch_tcp.setopts(socket, [active: socket_mode])

        # case :inet.getopts(socket, [:active]) do
        #     {:ok, opts} -> logger_debug "This is socket now: #{inspect opts}"
        #     {:error, reason} -> logger_debug "Error getting opts. Reason #{reason}"
        # end
    end

    defp is_absolute_path(path) do
        case ( path == String.trim_leading(path, "/") ) do
            true -> false
            false -> true
        end
    end

    defp update_client_cd(new_client_cd) do
        put(:client_cd, new_client_cd)
    end

    defp update_server_cd(new_server_cd) do
        put(:server_cd, new_server_cd)
    end

    defp update_file_offset(new_offset) do
        put(:offset, new_offset)
    end

    defp update_data_socket_info(new_ip, new_port) do
        put(:data_ip, new_ip)
        put(:data_port, new_port)
    end

    @doc """
    Simple module to check if the user can view a file/folder. Function attempts to
    perform a `String.trim_leading` call on the `current_path`. If `current_path` is
    part of the `root_path`, the `String.trim_leading` call will be able to remove the
    `root_path` string from the `current_path` string. If not, it will simply return
    the original `current_path`
    """
    defp allowed_to_read(current_path) do
        root_dir = get(:root_dir)
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

    defp get_info(cd,files) do
        list = for file <- files, do: Enum.join([cd, "/", file]) |> format_file_info
        Enum.join(list, "\r\n")
    end

    defp format_file_info(file) do
        root_dir = get(:root_dir)
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

    defp format_permissions(type, access) do
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

    defp format_month(month) do
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

    defp auth(socket) do
        expected_username = get(:username)
        expected_password = get(:password)
        data = receive do
            {:tcp, _socket, data} -> data
          end
        logger_debug "Username Given: #{inspect data}"
        "USER " <> username = to_string(data) |> String.trim()

        send_message(@ftp_GIVEPWORD,"Enter Password")
        # {:ok, data} = :gen_tcp.recv(socket, 0)
        data = receive do
            {:tcp, _socket, data} -> data
          end
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

    defp close_socket(socket) do
        case (socket == nil) do
            true -> logger_debug "Socket #{inspect socket} already closed."
            false ->
                case :gen_tcp.shutdown(socket, :read_write) do
                    :ok -> logger_debug "Socket #{inspect socket} successfully closed."
                    {:error, closed} -> logger_debug "Socket #{inspect socket} already closed."
                    {:error, other_reason} -> logger_debug "Error while attempting to close socket #{inspect socket}. Reason: #{other_reason}."
                end
        end
    end

    def put(key, value) do
        new_map = Process.get(:data_dictionary) |> Map.put(key, value)
        Process.put(:data_dictionary, new_map)
    end

    def get(key \\ nil) do
        case key do
          nil -> Process.get(:data_dictionary)
          _ -> Process.get(:data_dictionary) |> Map.get(key)
        end
    end

    def setup_dd(args) do
        initial_state = 
        %{
            root_dir: Map.get(args, :root_dir),
            ftp_data_pid: Map.get(args, :ftp_data_pid),
            control_socket: Map.get(args, :control_socket),
            data_socket: nil,
            username: Map.get(args, :username), 
            password: Map.get(args, :password), 
            control_ip: Map.get(args, :ip), 
            control_port: Map.get(args, :port),
            data_ip: nil,
            data_port: nil,
            client_cd: "/",
            server_cd: Map.get(args, :root_dir),
            file_offset: 0,
            transfer_type: nil,
            restart_time: Map.get(args, :restart_time),
            debug: Map.get(args, :debug),
            timeout: Map.get(args, :timeout),
            in_pasv_mode: false,
            aborted: false,
            listener_ref: Map.get(args, :listener_ref),
            ftp_logger_pid: Map.get(args, :ftp_logger_pid)
        }
        Process.put(:data_dictionary, initial_state)
        logger_debug "DD Set Up #{inspect get}..."
    end

end
