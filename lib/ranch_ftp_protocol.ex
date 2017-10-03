# start_link(ListenerPid, Socket, Transport, Opts) ->
#     Pid = spawn_link(?MODULE, init, [ListenerPid, Socket, Transport]),
#     {ok, Pid}.

# init(ListenerPid, Socket, Transport) ->
#     io:format("Got a connection!~n"),
#     ok.

defmodule RanchFtpProtocol do

    @timeout 600000
    require Logger
    
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
        Logger.debug("Got a connection!")
        Logger.debug("Starting Directory: #{start_directory}")
        :ranch_tcp.send(socket, "200 Welcome to FTP Server\r\n")
        sucessful_authentication = auth(socket, username, password)
        case sucessful_authentication do
            true -> 
                Logger.debug("User authenicated!\n")
                :ranch_tcp.send(socket, "230 Auth OK \r\n")
                FtpCommands.start(start_directory)
                loop_socket(socket, "")
            false ->
                Logger.debug("Invalid username or password\n")
                :ranch_tcp.send(socket, "430 Invalid username or password\r\n")
        end

    end

    def auth(socket, expected_username, expected_password) do
        {:ok, data} = :ranch_tcp.recv(socket, 0 , @timeout)
        Logger.debug "Username Given: #{inspect data}"
        "USER " <> username = data |> String.trim()

        :ranch_tcp.send(socket, "331 Enter Password\r\n")
        {:ok, data} = :ranch_tcp.recv(socket, 0 , @timeout)
        Logger.debug "Password Given: #{inspect data}"
        "PASS " <> password = data |> String.trim()
        # username = "apc"
        # password = "apc"
        
        valid_credentials = valid_username(expected_username, username) + valid_password(expected_password, password)
        case valid_credentials do
            0 -> true
            _ -> false
        end
    end

    def loop_socket(socket, buffer) do
        case :ranch_tcp.recv(socket, 0, @timeout) do
            {:ok, data} ->

                buffer2 = Enum.join([buffer, data])

                case parse_command(data, socket) do
                    {:valid_command, return_value} ->
                        response = return_value
                    :unknown_command ->
                        response = "202 command not implemented on this server\r\n"
                end
                Logger.debug "This is what I'm sending back: #{response}"
                :ranch_tcp.send(socket, response)
                Logger.debug "Sent: #{response}"
                loop_socket(socket, buffer2)
            {:error, :closed} ->
                Logger.debug("Connection has been closed.")
            {:error, other_reason} ->
                Logger.debug("Got an error #{inspect other_reason}")
        end
    end

    defp parse_command(data, socket) do
        Logger.debug("Got command #{inspect data}")
        command_executed = 
        cond do
            String.contains?(data, "LIST") == true ->
                cond  do
                    data == "LIST\r\n" ->
                        %{root_directory: root_directory, current_directory: cd, response: response, client_ip: client_ip, data_port: client_data_port} = FtpCommands.get_state
                        FtpCommands.list_files
                        new_state = FtpCommands.get_state
                        files = Map.get(new_state, :response)
                        :ranch_tcp.send(socket, "150 Transferring Data...\r\n")
                        client_ip = to_charlist(client_ip)
                        {:ok, data_socket} = :gen_tcp.connect(client_ip, client_data_port ,[:binary, packet: :line])
                        :ranch_tcp.send(data_socket, files)
                        :ranch_tcp.close(data_socket)
                        response = "226 Transfer Complete\r\n"
                        new_state=%{root_directory: root_directory, current_directory: cd, response: response, client_ip: nil, data_port: nil}
                        FtpCommands.set_state(new_state)
                        :ok
                    data == "LIST -a\r\n" ->
                        %{root_directory: root_directory, current_directory: cd, response: response, client_ip: client_ip, data_port: client_data_port} = FtpCommands.get_state
                        FtpCommands.list_files
                        new_state = FtpCommands.get_state
                        files = Map.get(new_state, :response)
                        :ranch_tcp.send(socket, "150 Transferring Data...\r\n")
                        client_ip = to_charlist(client_ip)
                        {:ok, data_socket} = :gen_tcp.connect(client_ip, client_data_port ,[:binary, packet: :line])
                        :ranch_tcp.send(data_socket, files)
                        :ranch_tcp.close(data_socket)
                        response = "226 Transfer Complete\r\n"
                        new_state=%{root_directory: root_directory, current_directory: cd, response: response, client_ip: nil, data_port: nil}
                        FtpCommands.set_state(new_state)
                        :ok
                    true ->
                        "LIST " <> dir_name = data |> String.trim()
                        %{root_directory: root_directory, current_directory: cd, response: response, client_ip: client_ip, data_port: client_data_port} = FtpCommands.get_state
                        FtpCommands.list_files dir_name
                        new_state = FtpCommands.get_state
                        files = Map.get(new_state, :response)
                        :ranch_tcp.send(socket, "150 Transferring Data...\r\n")
                        client_ip = to_charlist(client_ip)
                        {:ok, data_socket} = :gen_tcp.connect(client_ip, client_data_port ,[:binary, packet: :line])
                        :ranch_tcp.send(data_socket, files)
                        :ranch_tcp.close(data_socket)
                        response = "226 Transfer Complete\r\n"
                        new_state=%{root_directory: root_directory, current_directory: cd, response: response, client_ip: nil, data_port: nil}
                        FtpCommands.set_state(new_state)
                        :ok
                    end
            String.contains?(data, "RETR") == true ->
                "RETR " <> file = data |> String.trim()
                current_state = FtpCommands.get_state
                Logger.debug "This is current_state #{inspect current_state}"
                %{root_directory: root_directory, current_directory: cd, response: response, client_ip: client_ip, data_port: client_data_port} = FtpCommands.get_state
                
                full_file_path = Enum.join([cd, "/" ,file])
                case File.exists?(full_file_path) do
                    true -> 
                        :ranch_tcp.send(socket, "150 Transferring Data...\r\n")
                        client_ip = to_charlist(client_ip)
                        {:ok, data_socket} = :gen_tcp.connect(client_ip, client_data_port ,[:binary, packet: :line])
                        :ranch_tcp.sendfile(data_socket, full_file_path)
                        :ranch_tcp.close(data_socket)
                        response = "226 Transfer Complete\r\n"
                    false ->
                        response = "550 File does not exist. Not transferring.\r\n"
                end
                
                new_state=%{root_directory: root_directory, current_directory: cd, response: response, client_ip: nil, data_port: nil}
                FtpCommands.set_state(new_state)
                :ok

            String.contains?(data, "STOR") == true ->
                "STOR " <> file = data |> String.trim()
                current_state = FtpCommands.get_state
                Logger.debug "This is current_state #{inspect current_state}"
                %{root_directory: root_directory, current_directory: cd, response: response, client_ip: client_ip, data_port: client_data_port} = FtpCommands.get_state
                
                full_file_path = Enum.join([cd, "/" ,file])
                case File.exists?(full_file_path) do
                    true -> 
                        File.rm!(full_file_path)
                    false ->
                        :ok
                end
                
                :ranch_tcp.send(socket, "150 Opening Data Socket for transfer...\r\n")
                :ranch_tcp.send(socket, "227 Entering Passive Mode\r\n")
                client_ip = to_charlist(client_ip)
                {:ok, data_socket} = :gen_tcp.connect(client_ip, client_data_port ,[active: false, mode: :binary, packet: :raw])
                #:ranch_tcp.send(socket, "227 Entering Passive Mode\r\n")
                {:ok, packet} = receive_file(data_socket)
                Logger.debug("This is packet: #{inspect packet}")
                a = byte_size(packet)
                Logger.debug("This is size: #{inspect a}")
                :ranch_tcp.close(data_socket)
                :ranch_tcp.shutdown(data_socket, :read_write)
                :file.write_file(to_charlist(full_file_path), packet)
                :ranch_tcp.send(socket, "226 Transfer Complete\r\n")
                response = "200 Okay\r\n"

                new_state=%{root_directory: root_directory, current_directory: cd, response: response, client_ip: nil, data_port: nil}
                FtpCommands.set_state(new_state)
                :ok
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
            String.contains?(data, "PORT") == true ->
                "PORT " <> port_data = data |> String.trim()
                [ h1, h2, h3, h4, p1, p2] = String.split(port_data, ",")
                port_number = String.to_integer(p1)*256 + String.to_integer(p2)
                ip = Enum.join([h1, h2, h3, h4], ".")
                FtpCommands.port( ip, port_number)
                :ok
            String.contains?(data, "QUIT") == true ->
                FtpCommands.quit
                :ok
            true ->
                Logger.debug "This is data: #{inspect data}"
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
            {:error, reason} ->
                Logger.error "reason: "
                {:ok, packet}
        end
    end

end