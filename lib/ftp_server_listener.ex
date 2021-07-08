defmodule FtpServerListener do
    @moduledoc """
    Documentation for FtpServerListener. Used to start the "control" socket of the FTP Server
    """
    use GenServer


    def start_link(args) do
        server_name = Map.get(args, :server_name)
        name = Enum.join([server_name, "_ftp_server_listener"]) |> String.to_atom
        GenServer.start_link(__MODULE__, args, name: name)
    end


    def init(state) do
        Process.flag(:trap_exit, true)
        ip = Map.get(state, :ip)
        port = Map.get(state, :port)
        server_name = Map.get(state, :server_name)

        IO.puts "FTP Server #{server_name} running. IP: #{inspect ip} Port: #{inspect port}"
        listener_name = Enum.join([server_name, "_control_socket"]) |> String.to_atom
        :ranch.start_listener(listener_name, 10, :ranch_tcp, [port: port, ip: ip], FtpServer, [state])
        {:ok, Map.put(state, :listener_name, listener_name)}
    end

    def terminate(_reason, _state = %{listener_name: listener_name}), do: :ranch.stop_listener(listener_name)
end
