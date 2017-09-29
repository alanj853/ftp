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
        pid = spawn_link(__MODULE__, :init, [listener_pid, socket, transport])
        {:ok, pid}
    end

    def init(listener_pid, socket, transport) do
        :ranch.accept_ack(listener_pid)
        Logger.debug("Got a connection!")
        :ranch_tcp.send(socket, "200 Welcome to FTP Server\r\n")
        auth(socket, transport, "apc", "apc")
    end

    def auth(socket, transport, expected_username, expected_password) do
        {:ok, data} = :ranch_tcp.recv(socket, 0 , @timeout)
        Logger.debug "Username Given: #{inspect data}"
        "USER " <> username = data |> String.trim()

        :ranch_tcp.send(socket, "331 Enter Password\r\n")
        {:ok, data} = :ranch_tcp.recv(socket, 0 , @timeout)
        Logger.debug "Password Given: #{inspect data}"
        "PASS " <> password = data |> String.trim()
        
        valid_credentials = valid_username(expected_username, username) + valid_password(expected_password, password)
        case valid_credentials do
            0 ->
                Logger.debug("User authenicated!\n")
                :ranch_tcp.send(socket, "230 Auth OK \r\n")
                FtpSession.start(:connected)
                loop_socket(socket, "")
                :ok
            _ ->
                Logger.debug("Invalid username or password\n")
                :ranch_tcp.send(socket, "430 Invalid username or password\r\n")
            end

    end

    def loop_socket(socket, buffer) do
        case :ranch_tcp.recv(socket, 0, @timeout) do
            {:ok, data} ->

                buffer2 = Enum.join([buffer, data])

                case parse_command(data) do
                    {:valid, return_value} ->
                        response = return_value
                    {:invalid, command} ->
                        response = "500 Bad command\r\n"
                    {:incomplete, command} ->
                        loop_socket(socket, data)
                end
                Logger.debug "This is what I'm sending back: #{response}"
                :ranch_tcp.send(socket, response)
                loop_socket(socket, buffer2)
            {:error, reason} ->
                Logger.debug("Got an error #{inspect reason}")
        end
    end

    defp parse_command(data) do
        Logger.debug("Got command #{inspect data}")
        command_executed = 
        cond do
            String.contains?(data, "LIST") == true ->
                cond  do
                    data == "LIST\r\n" ->
                        FtpSession.list_files
                        :executed
                    data == "LIST -a\r\n" ->
                        FtpSession.list_files
                        :executed
                    true ->
                        "LIST " <> dir_name = data |> String.trim()
                        FtpSession.list_files dir_name
                        :executed
                    end
            String.contains?(data, "PWD") == true -> 
                FtpSession.current_directory
                :executed
            String.contains?(data, "CWD") == true ->
                "CWD " <> dir_name = data |> String.trim()
                FtpSession.change_directory dir_name
                :executed
            String.contains?(data, "MKD ") == true ->
                "MKD " <> dir_name = data |> String.trim()
                FtpSession.make_directory dir_name
                :executed
            String.contains?(data, "RMD ") == true ->
                "RMD " <> dir_name = data |> String.trim()
                FtpSession.remove_directory dir_name
                :executed
            String.contains?(data, "DELE ") == true ->
                "DELE " <> dir_name = data |> String.trim()
                FtpSession.remove_file dir_name
                :executed
            String.contains?(data, "SYST") == true ->
                FtpSession.system_type
                :executed
            String.contains?(data, "FEAT") == true ->
                FtpSession.feat
                :executed
            String.contains?(data, "TYPE") == true ->
                FtpSession.type
                :executed
            String.contains?(data, "PASV") == true ->
                FtpSession.pasv
                :executed
            String.contains?(data, "PORT") == true ->
                FtpSession.port
                :executed
            true ->
                Logger.debug "This is data: #{inspect data}"
                {:valid, "valid command"}
                :unknown_command
        end

        case command_executed do
            :unknown_command ->
                Logger.debug "This is data: #{inspect data}"
                {:valid, "202 command not implemented on this server\r\n"}
            _ ->
                ## There appears to be a bug in GenServer, whereby the previous state gets returned upon running one of 
                ## the FtpSession commands above. Therefore, each command needed to be run twice for the correct info to be 
                ## returned. Hence, we run get_state here so that each of the commands only needs to be run once.
                %{connection_status: status, current_directory: cd, response: response} = FtpSession.get_state
                {:valid, response}
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

end