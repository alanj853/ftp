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
        {:ok, data} = :ranch_tcp.recv(socket, 0 , @timeout)
        auth(socket, transport, data)
    end

    def auth(socket, transport, data) do
        Logger.debug("User authenicated!\n")
        :ranch_tcp.send(socket, "230 Auth OK \r\n")
        FtpSession.start(:connected)
        loop_socket(socket, "")
        :ok
    end

    def loop_socket(socket, buffer) do
        case :ranch_tcp.recv(socket, 0, @timeout) do
            {:ok, data} ->

                buffer2 = Enum.join([buffer, data])

                case parse_command(data) do
                    {:valid, return_value} ->
                        response = "200 #{return_value}\r\n"
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
        cond do
            String.contains?(data, "LIST ") == true ->
                "LIST " <> dir_name = data |> String.trim()
                %{connection_status: status, current_directory: cd, response: response} = FtpSession.list_files dir_name
                {:valid, response}
            String.contains?(data, "LIST") == true -> 
                %{connection_status: status, current_directory: cd, response: response} = FtpSession.list_files
                {:valid, response}
            String.contains?(data, "PWD") == true -> 
                %{connection_status: status, current_directory: cd, response: response} = FtpSession.current_directory
                {:valid, response}
            String.contains?(data, "CWD") == true ->
                "CWD " <> dir_name = data |> String.trim()
                %{connection_status: status, current_directory: cd, response: response} = FtpSession.change_directory dir_name
                {:valid, response}
            true ->
                Logger.debug "This is data: #{inspect data}"
                {:valid, "valid command"}
        end
    end

end