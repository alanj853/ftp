# start_link(ListenerPid, Socket, Transport, Opts) ->
#     Pid = spawn_link(?MODULE, init, [ListenerPid, Socket, Transport]),
#     {ok, Pid}.

# init(ListenerPid, Socket, Transport) ->
#     io:format("Got a connection!~n"),
#     ok.

defmodule FtpProtocol do

    require Logger

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
    
    ## Debug can be set at 3 levels
    ## 0 - No debug is printed at all
    ## 1 - Only direct logger_debug calls are printed, but NOT copies of messages send to client
    ## 2 - All debug is printed, including copies of messages send to client
    @debug 2
    
    def start_link(listener_pid, socket, transport, opts) do
        {:ok, map} = Enum.fetch(opts,0)
        starting_directory = Map.get(map, :directory)
        username = Map.get(map, :username)
        password = Map.get(map, :password)
        pid = spawn_link(__MODULE__, :init, [listener_pid, socket, starting_directory, username, password])
        {:ok, pid}
    end

    def init(listener_pid, socket, start_directory, username, password) do
        :ranch.accept_ack(listener_pid)
        logger_debug("Got a connection!")
        logger_debug("Starting Directory: #{start_directory}")
        send_message(@ftp_OK, "Welcome to FTP Server", socket)
        sucessful_authentication = auth(socket, username, password)
        case sucessful_authentication do
            true -> 
                send_message(@ftp_LOGINOK, "User Authenticated", socket)
                FtpInfo.start(start_directory)
                FtpData.start(nil, nil, nil, 0)
                serve(socket, "")
            false ->
                logger_debug("Invalid username or password\n")
                :ranch_tcp.send(socket, "430 Invalid username or password\r\n")
        end
    end

    defp auth(socket, expected_username, expected_password) do
        {:ok, data} = :ranch_tcp.recv(socket, 0 , @timeout)
        logger_debug "Username Given: #{inspect data}"
        "USER " <> username = data |> String.trim()

        send_message(@ftp_GIVEPWORD,"Enter Password", socket)
        {:ok, data} = :ranch_tcp.recv(socket, 0 , @timeout)
        logger_debug "Password Given: #{inspect data}"
        "PASS " <> password = data |> String.trim()
        
        valid_credentials = valid_username(expected_username, username) + valid_password(expected_password, password)
        case valid_credentials do
            0 -> true
            _ -> false
        end
    end

    defp serve(socket, buffer) do
        ## wait for command from client
        case :ranch_tcp.recv(socket, 0, @timeout) do
            {:ok, command} ->
                buffer2 = Enum.join([buffer, command])

                {code, response} = get_command(command, socket)
                case code do
                    :ok -> :ok
                    _ -> send_message(code, response, socket)
                end
                serve(socket, buffer2)
            {:error, :closed} ->
                logger_debug("Connection has been closed.")
            {:error, other_reason} ->
                logger_debug("Got an error #{inspect other_reason}")
        end
        :ranch_tcp.close(socket)
    end

    defp get_command(command, socket) do
        logger_debug("FROM CLIENT: #{command}")
        {code, response} =
        cond do 
            String.contains?(command, "LIST") == true -> handle_list(socket, command)
            String.contains?(command, "TYPE") == true -> handle_type(socket, command)
            String.contains?(command, "STRU") == true -> handle_stru(socket, command)
            # String.contains?(command, "USER") == true -> handle_user(socket, command)
            String.contains?(command, "QUIT") == true -> handle_quit(socket, command)
            String.contains?(command, "PORT") == true -> handle_port(socket, command)
            String.contains?(command, "RETR") == true -> handle_retr(socket, command)
            String.contains?(command, "STOR") == true -> handle_stor(socket, command)
            String.contains?(command, "NOOP") == true -> handle_noop(socket, command)
            # String.contains?(command, "DELE") == true -> handle_dele(socket, command)
            # String.contains?(command, "MKD") == true -> handle_mkd(socket, command)
            # String.contains?(command, "RMD") == true -> handle_rmd(socket, command)
            String.contains?(command, "SIZE") == true -> handle_size(socket, command)
            String.contains?(command, "PASV") == true -> handle_pasv(socket, command)
            String.contains?(command, "SYST") == true -> handle_syst(socket, command)
            String.contains?(command, "FEAT") == true -> handle_feat(socket, command)
            String.contains?(command, "PWD") == true -> handle_pwd(socket, command)
            String.contains?(command, "CWD") == true -> handle_cwd(socket, command)
            String.contains?(command, "REST") == true -> handle_rest(socket, command)
            String.contains?(command, "MODE") == true -> handle_mode(socket, command)
            String.contains?(command, "ABOR") == true -> handle_abor(socket, command)
            true -> {@ftp_COMMANDNOTIMPL, "Command not implemented on this server"}
        end

    end

    ## COMMAND HANDLERS

    def handle_noop(socket, command) do
        {@ftp_NOOPOK, "No Operation"}
    end

    def handle_feat(socket, command) do
        {@ftp_NOFEAT, "no-features"}
    end

    def handle_pasv(socket, command) do
        {@ftp_PASVOK, "Entering Passive Mode"}
    end

    def handle_abor(socket, command) do
        current_state = FtpInfo.get_state
        # data_socket = Map.get(current_state, :data_socket)
        # error = 
        # case data_socket do
        #     nil -> "(socket already closed)"
        #     _ ->
        #         case :ranch_tcp.close(data_socket) do
        #             {:ok, _} -> ""
        #             {:error, reason} -> "(Got error #{inspect reason})"
        #         end
        # end
        FtpData.close_socket
        send_message(@ftp_ABORT, "Connect Closed . Transfer Aborted", socket)
        {@ftp_ABORTOK, "Abort Command Successful"}
    end

    def handle_type(socket, command) do
        "TYPE " <> type = command |> String.trim()
        case type do
            "I" -> {@ftp_TYPEOK, "Image"}
            "A" -> {@ftp_TYPEOK, "ASCII"}
            "E" -> {@ftp_TYPEOK, "EBCDIC"}
            _ -> {@ftp_TYPEOK, "ASCII Non-print"}
        end
    end

    def handle_rest(socket, command) do
        "REST " <> offset = command |> String.trim()
        update_file_offset(String.to_integer(offset))
        {@ftp_RESTOK, "Rest Supported. Offset set to #{offset}"}
    end

    def handle_syst(socket, command) do
        {@ftp_SYSTOK, "UNIX Type: L8"}
    end

    def handle_stru(socket, command) do
        {@ftp_STRUOK, "FILE"}
    end

    def handle_quit(socket, command) do
        {@ftp_GOODBYE, "Goodbye"}
    end

    def handle_mode(socket, command) do
        "MODE " <> mode = command |> String.trim()
        case mode do
            "C" -> {@ftp_MODEOK, "Compressed"}
            "B" -> {@ftp_MODEOK, "Block"}
            _ -> {@ftp_MODEOK, "Stream"}
        end
    end

    def handle_port(socket, command) do
        "PORT " <> port_data = command |> String.trim()
        [ h1, h2, h3, h4, p1, p2] = String.split(port_data, ",")
        port_number = String.to_integer(p1)*256 + String.to_integer(p2)
        port = to_string(port_number)
        ip = Enum.join([h1, h2, h3, h4], ".")
        update_data_socket_info(ip, port_number)
        {@ftp_PORTOK, "Client IP: #{ip}. Client Port: #{port}"}
    end

    def handle_list(socket, command) do
        case command do
            "LIST\r\n" -> 
                %{root_dir: root_dir, server_cd: server_cd , client_cd: current_client_working_directory, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset } = FtpInfo.get_state
                {:ok, files} = File.ls(server_cd)
                file_info = get_info(server_cd, files)
                file_info = Enum.join(["(", file_info, ")"])
                send_message(@ftp_DATACONN, "Opening Data Socket for transfer of ls command...", socket)
                ip = to_charlist(ip)
                {:ok, data_socket} = :gen_tcp.connect(ip, port ,[active: false, mode: :binary, packet: :raw])
                :ranch_tcp.send(data_socket, file_info)
                :ranch_tcp.close(data_socket)
                reset_data_socket()
                {@ftp_TRANSFEROK, "Transfer Complete"}
            "LIST -a\r\n" -> 
                %{root_dir: root_dir, server_cd: server_cd , client_cd: current_client_working_directory, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset } = FtpInfo.get_state
                {:ok, files} = File.ls(server_cd)
                file_info = get_info(server_cd, files)
                file_info = Enum.join(["(", file_info, ")"])
                send_message(@ftp_DATACONN, "Opening Data Socket for transfer of ls command...", socket)
                ip = to_charlist(ip)
                {:ok, data_socket} = :gen_tcp.connect(ip, port ,[active: false, mode: :binary, packet: :raw])
                :ranch_tcp.send(data_socket, file_info)
                :ranch_tcp.close(data_socket)
                reset_data_socket()
                {@ftp_TRANSFEROK, "Transfer Complete"}
                
        end
    end

    def handle_size(socket, command) do
        "SIZE " <> path = command |> String.trim()
        current_client_working_directory = FtpInfo.get_state |> Map.get(:client_cd)
        current_server_working_directory = FtpInfo.get_state |> Map.get(:server_cd)
        working_path = 
        case is_absolute_path(path) do
            true -> Enum.join([current_server_working_directory, path])
            false ->Enum.join([current_server_working_directory, current_client_working_directory ,path])
        end

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

    def handle_stor(socket, command) do
        "STOR " <> path = command |> String.trim()
        %{root_dir: root_dir, server_cd: current_server_working_directory , client_cd: current_client_working_directory, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset } = FtpInfo.get_state
        working_path = 
        case is_absolute_path(path) do
            true -> Enum.join([current_server_working_directory, path])
            false ->Enum.join([current_server_working_directory, current_client_working_directory ,path])
        end

        case allowed_to_write(working_path) do
            true ->
                logger_debug "working_dir: #{working_path}"
                case File.exists?(working_path) do
                    true -> File.rm(working_path)
                    false -> :ok
                end
                send_message(@ftp_DATACONN, "Opening Data Socket to receive file...", socket)
                ip = to_charlist(ip)
                {:ok, data_socket} = :gen_tcp.connect(ip, port ,[active: false, mode: :binary, packet: :raw])
                {:ok, file} = receive_file(data_socket)
                logger_debug("This is packet: #{inspect file}")
                file_size = byte_size(file)
                logger_debug("This is size: #{inspect file_size}")
                :ranch_tcp.close(data_socket)
                :ranch_tcp.shutdown(data_socket, :read_write)
                :file.write_file(to_charlist(working_path), file)
                reset_data_socket()
                {@ftp_TRANSFEROK, "File Received"}
            false ->
                {@ftp_NOPERM, "You don't have permission to write to this directory ('#{path}')."}
        end
    end

    def handle_retr(socket, command) do
        "RETR " <> path = command |> String.trim()
        %{root_dir: root_dir, server_cd: current_server_working_directory , client_cd: current_client_working_directory, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset } = FtpInfo.get_state
        working_path = 
        case is_absolute_path(path) do
            true -> Enum.join([current_server_working_directory, path])
            false ->Enum.join([current_server_working_directory, current_client_working_directory ,path])
        end

        path_exists = File.exists?(working_path)
        is_directory = File.dir?(working_path)
        have_read_access = allowed_to_read(working_path)
        
        cond do
            is_directory == true -> {@ftp_FILEFAIL, "Current path '#{path}' is a directory."}
            path_exists == false -> {@ftp_FILEFAIL, "Current directory '#{path}' does not exist."}
            have_read_access == false -> {@ftp_NOPERM, "You don't have permission to read from this directory ('#{path}')."}
            true -> 
                send_message(@ftp_DATACONN, "Opening Data Socket for transfer of file #{path} from offset #{offset}...", socket)
                ip = to_charlist(ip)
                x= FtpData.create_socket(ip, port)
                IO.puts(x)
                #FtpData.retrieve(working_path, offset)
                #{:ok, data_socket} = :gen_tcp.connect(ip, port ,[active: false, mode: :binary, packet: :raw])
                #:ranch_tcp.sendfile(data_socket, working_path, offset, 0)
                #:ranch_tcp.close(data_socket)
                #reset_data_socket()
                #{@ftp_TRANSFEROK, "Transfer Complete"}
                {0, :ok}
        end
    end

    def handle_pwd(socket, command) do
        working_directory = FtpInfo.get_state |> Map.get(:client_cd)
        {@ftp_PWDOK, "\"#{working_directory}\""}
    end

    def handle_cwd(socket, command) do
        "CWD " <> path = command |> String.trim()
        path = 
        case String.contains?(path, "..") do 
            true -> handle_cd_up(path)

            false -> path
        end

        current_client_working_directory = FtpInfo.get_state |> Map.get(:client_cd)
        current_server_working_directory = FtpInfo.get_state |> Map.get(:server_cd)
        root_directory = FtpInfo.get_state |> Map.get(:root_dir)

        working_path = 
        case is_absolute_path(path) do
            true -> Enum.join([root_directory, path])
            false ->Enum.join([current_server_working_directory, current_client_working_directory ,path])
        end
        logger_debug "This is working path: #{working_path}"
        path_exists = File.exists?(working_path)
        is_directory = File.dir?(working_path)
        have_read_access = allowed_to_read(working_path)
        
        cond do
            is_directory == false -> {@ftp_FILEFAIL, "Current path '#{path}' is not a directory."}
            path_exists == false -> {@ftp_FILEFAIL, "Current directory '#{path}' does not exist."}
            have_read_access == false -> {@ftp_NOPERM, "You don't have permission to read from this directory ('#{path}')."}
            true -> 
                new_server_working_directory = String.trim_trailing(working_path, "/")
                new_client_working_directory = String.trim_leading(working_path, root_directory)
                update_client_cd(new_client_working_directory)
                update_server_cd(new_server_working_directory)
                {@ftp_CWDOK, "Current directory changed to '#{new_client_working_directory}''"}
        end
    end

    defp get_command1(data, socket) do
        Logger.debug "i get here"
        logger_debug("Got command #{inspect data}")

        Logger.debug "i get here"
        command_executed = 
        cond do
            String.contains?(data, "LIST") == true ->
                cond  do
                    data == "LIST\r\n" ->
                        %{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: client_ip, data_port: client_data_port} = FtpCommands.get_state
                        FtpCommands.list_files
                        new_state = FtpCommands.get_state
                        files = Map.get(new_state, :response)
                        :ranch_tcp.send(socket, "150 Transferring Data...\r\n")
                        client_ip = to_charlist(client_ip)
                        {:ok, data_socket} = :gen_tcp.connect(client_ip, client_data_port ,[:binary, packet: :line])
                        :ranch_tcp.send(data_socket, files)
                        :ranch_tcp.close(data_socket)
                        response = "226 Transfer Complete\r\n"
                        new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: nil, data_port: nil}
                        FtpCommands.set_state(new_state)
                        :ok
                    data == "LIST -a\r\n" ->
                        %{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: client_ip, data_port: client_data_port} = FtpCommands.get_state
                        FtpCommands.list_files
                        new_state = FtpCommands.get_state
                        files = Map.get(new_state, :response)
                        :ranch_tcp.send(socket, "150 Transferring Data...\r\n")
                        client_ip = to_charlist(client_ip)
                        {:ok, data_socket} = :gen_tcp.connect(client_ip, client_data_port ,[:binary, packet: :line])
                        :ranch_tcp.send(data_socket, files)
                        :ranch_tcp.close(data_socket)
                        response = "226 Transfer Complete\r\n"
                        new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: nil, data_port: nil}
                        FtpCommands.set_state(new_state)
                        :ok
                    true ->
                        "LIST " <> dir_name = data |> String.trim()
                        %{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: client_ip, data_port: client_data_port} = FtpCommands.get_state
                        FtpCommands.list_files dir_name
                        new_state = FtpCommands.get_state
                        files = Map.get(new_state, :response)
                        :ranch_tcp.send(socket, "150 Transferring Data...\r\n")
                        client_ip = to_charlist(client_ip)
                        {:ok, data_socket} = :gen_tcp.connect(client_ip, client_data_port ,[:binary, packet: :line])
                        :ranch_tcp.send(data_socket, files)
                        :ranch_tcp.close(data_socket)
                        response = "226 Transfer Complete\r\n"
                        new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: nil, data_port: nil}
                        FtpCommands.set_state(new_state)
                        :ok
                    end
            String.contains?(data, "RETR") == true ->
                "RETR " <> file = data |> String.trim()
                file = String.replace(file, "//", "/")
                current_state = FtpCommands.get_state
                logger_debug "This is current_state #{inspect current_state}"
                %{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: client_ip, data_port: client_data_port} = FtpCommands.get_state
                
                cd = 
                case cd do
                    "/" -> ""
                    _ -> cd
                end
                full_file_path = Enum.join([root_directory, cd, "/" ,file])
                #IO.puts "This is ffp: #{full_file_path}"
                case File.exists?(full_file_path) do
                    true -> 
                        :ranch_tcp.send(socket, "150 Transferring Data...\r\n")
                        client_ip = to_charlist(client_ip)
                        {:ok, data_socket} = :gen_tcp.connect(client_ip, client_data_port ,[:binary, packet: :line])
                        :ranch_tcp.sendfile(data_socket, full_file_path, 36, 0)
                        :ranch_tcp.close(data_socket)
                        response = "226 Transfer Complete\r\n"
                    false ->
                        Logger.debug "File #{full_file_path} does not exist"
                        response = "550 File does not exist. Not transferring.\r\n"
                end
                
                new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: nil, data_port: nil}
                FtpCommands.set_state(new_state)
                :ok

            String.contains?(data, "STOR") == true ->
                "STOR " <> file = data |> String.trim()
                current_state = FtpCommands.get_state
                logger_debug "This is current_state #{inspect current_state}"
                %{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: client_ip, data_port: client_data_port} = FtpCommands.get_state
                cd = 
                case cd do
                    "/" -> ""
                    _ -> cd
                end
                full_file_path = Enum.join([root_directory, cd, "/" ,file])
                case File.exists?(full_file_path) do
                    true -> 
                        File.rm!(full_file_path)
                    false ->
                        :ok
                end
                :ranch_tcp.send(socket, "150 Opening Data Socket for transfer...\r\n")
                client_ip = to_charlist(client_ip)
                {:ok, data_socket} = :gen_tcp.connect(client_ip, client_data_port ,[active: false, mode: :binary, packet: :raw])
                {:ok, packet} = receive_file(data_socket)
                logger_debug("This is packet: #{inspect packet}")
                a = byte_size(packet)
                logger_debug("This is size: #{inspect a}")
                :ranch_tcp.close(data_socket)
                :ranch_tcp.shutdown(data_socket, :read_write)
                :file.write_file(to_charlist(full_file_path), packet)
                response = "226 Transfer Complete\r\n"
                new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: nil, data_port: nil}
                FtpCommands.set_state(new_state)
                :okcurrent_state = 
            String.contains?(data, "PWD") == true -> 
                FtpCommands.current_directory
                :ok
            String.contains?(data, "CWD") == true ->
                "CWD " <> dir_name = data |> String.trim()
                FtpCommands.change_working_directory dir_name
                :ok
            String.contains?(data, "MKD ") == true ->
                "MKD " <> dir_name = data |> String.trim()
                FtpCommands.make_directory dir_name
                :ok
            String.contains?(data, "RMD ") == true ->
                "RMD " <> dir_name = data |> String.trim()
                FtpCommands.remove_directory dir_name
                :ok
            String.contains?(data, "DELE ") == true ->
                "DELE " <> dir_name = data |> String.trim()
                FtpCommands.remove_file dir_name
                :ok
            String.contains?(data, "SYST") == true ->
                FtpCommands.system_type
                :ok
            String.contains?(data, "FEAT") == true ->
                FtpCommands.feat
                :ok
            String.contains?(data, "TYPE") == true ->
                FtpCommands.type
                :ok
            String.contains?(data, "PASV") == true ->
                FtpCommands.pasv
                :ok
            String.contains?(data, "SIZE") == true ->
                
                "SIZE " <> file = data |> String.trim()
                current_state = FtpCommands.get_state
                logger_debug "This is current_state #{inspect current_state}"
                %{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: client_ip, data_port: client_data_port} = FtpCommands.get_state
                cd = 
                case cd do
                    "/" -> ""
                    _ -> cd
                end
                full_file_path = Enum.join([root_directory, cd, "/" ,file])

                case File.exists?(full_file_path) do
                    true -> 
                        {:ok, info} = File.stat(full_file_path)
                        file_size = Map.get(info, :size)
                        response = "213 #{file_size}\r\n"
                    false ->
                        Logger.debug "File #{full_file_path} does not exist"
                        response = "550 File does not exist. Not transferring.\r\n"
                end
                new_state=%{id: id, root_directory: root_directory, current_directory: cd, response: response, client_ip: nil, data_port: nil}
                FtpCommands.set_state(new_state)
                :ok
            String.contains?(data, "PORT") == true ->
                "PORT " <> port_data = data |> String.trim()
                [ h1, h2, h3, h4, p1, p2] = String.split(port_data, ",")
                port_number = String.to_integer(p1)*256 + String.to_integer(p2)
                ip = Enum.join([h1, h2, h3, h4], ".")
                FtpCommands.port( ip, port_number)
                :ok
            String.contains?(data, "REST") == true ->
                FtpCommands.rest
                :ok
            String.contains?(data, "QUIT") == true ->
                FtpCommands.quit
                :ok
            true ->
                logger_debug "This is data: #{inspect data}"
                :unknown_command
        end

        case command_executed do
            :unknown_command ->
                :unknown_command
            :ok ->
                ## There appears to be a bug in GenServer, whereby the previous state gets returned upon running one of 
                ## the FtpCommands commands above. Therefore, each command needed to be run twice for the correct info to be 
                ## returned. Hence, we run get_state here so that each of the commands only needs to be run once.
                response = FtpCommands.get_state |> Map.get(:response)
                {:valid_command, response}
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

    defp receive_file(data_socket, packet \\ "") do
        case :gen_tcp.recv(data_socket, 0) do
            {:ok, new_packet} ->
                new_packet = Enum.join([packet, new_packet])
                receive_file(data_socket, new_packet)
            {:error, :closed} ->
                logger_debug "Finished receiving file."
                {:ok, packet}
            {:error, other_reason} ->
                logger_debug "This is reason2: #{other_reason}"
                {:ok, packet}
        end
    end

    defp logger_debug(message, id \\ "") do
        case @debug do
            0 -> :ok
            _ -> Logger.debug(message)
        end
    end

    defp send_message(code, msg, socket) do
        message = Enum.join([to_string(code), " " , msg, "\r\n"])
        case @debug do
            2 -> 
                logger_debug("Sending message below to client")
                logger_debug("FROM SERVER #{message}")
                logger_debug("Message sent to client")
            _ -> :ok
        end
        :ranch_tcp.send(socket, message)
    end

    defp is_absolute_path(path) do
        case ( path == String.trim_leading(path, "/") ) do
            true -> false
            false -> true
        end
    end

    defp update_client_cd(new_client_dir) do
        %{root_dir: root_dir, server_cd: server_cd , client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset } = FtpInfo.get_state
        new_state = %{root_dir: root_dir, server_cd: server_cd ,client_cd: new_client_dir, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset }
        FtpInfo.set_state new_state
    end

    defp update_server_cd(new_server_dir) do
        %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset } = FtpInfo.get_state
        new_state = %{root_dir: root_dir, server_cd: new_server_dir ,client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset }
        FtpInfo.set_state new_state
    end

    defp update_file_offset(new_offset) do
        %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset } = FtpInfo.get_state
        new_state = %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: new_offset }
        FtpInfo.set_state new_state
    end

    defp update_data_socket(new_data_socket) do
        %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset } = FtpInfo.get_state
        new_state = %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: new_data_socket, data_ip: ip, data_port: port, type: type, offset: offset }
        FtpInfo.set_state new_state
    end

    defp update_data_socket_info(new_ip, new_port) do
        %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: data_socket, data_ip: ip, data_port: port, type: type, offset: offset } = FtpInfo.get_state
        new_state = %{root_dir: root_dir, server_cd: server_cd ,client_cd: client_cd, data_socket: data_socket, data_ip: new_ip, data_port: new_port, type: type, offset: offset }
        FtpInfo.set_state new_state
    end

    defp reset_data_socket() do
        update_data_socket(nil)
        update_data_socket_info(nil, nil)
        update_file_offset(0)
    end

    @doc """
    Simple module to check if the user can view a file/folder. Function attempts to 
    perform a `String.trim_leading` call on the `current_path`. If `current_path` is 
    part of the `root_path`, the `String.trim_leading` call will be able to remove the 
    `root_path` string from the `current_path` string. If not, it will simply return 
    the original `current_path`
    """
    defp allowed_to_read(current_path) do
        root_dir = FtpInfo.get_state |> Map.get(:root_dir)
        case (current_path == root_dir) do
        true ->
            true
        false ->
            case (current_path == String.trim_leading(current_path, root_dir)) do
            true ->
                #logger_debug id, "#{current_path} is not on #{root_dir}"
                false
            false ->
                #logger_debug id, "#{current_path} is on #{root_dir}"
                true
            end
        end

        true
    end

    defp allowed_to_write(current_path) do
        true
    end

    defp handle_cd_up(current_path) do
        current_path = String.trim_trailing(current_path, "/../")
        current_path = String.trim_trailing(current_path, "/..")
        case current_path do
            "" -> "/"
            ".." ->
                IO.puts "I go here"
                list = FtpInfo.get_state |> Map.get(:client_cd) |> String.split("/")
                list_size = Enum.count(list)
                { _, new_list} = List.pop_at(list, (list_size - 1))
                case (new_list == [""]) do
                    true -> "/"
                    false -> Enum.join(new_list, "/")
                end
            _ ->
                list = String.split(current_path, "/")
                list_size = Enum.count(list)
                { _, new_list} = List.pop_at(list, (list_size - 1))
                Enum.join(new_list, "/")
        end
    end

    def get_info(cd,files) do
        list = for file <- files, do: Enum.join([cd, "/", file]) |> format_file_info()
        Enum.join(list, "\r\n")
    end

    def format_file_info(file) do
        state = FtpInfo.get_state
        root_dir = Map.get(state, :root_dir)
        name = String.trim_leading(file, root_dir)
        IO.puts "getting info for #{file}"
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
end