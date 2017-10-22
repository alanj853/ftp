defmodule FtpServerListener do
    use GenServer

    def start_link(args) do
        server_name = Map.get(args, :server_name)
        name = Enum.join([server_name, "_ftp_server_listener"]) |> String.to_atom
        GenServer.start_link(__MODULE__, args, name: name)
    end

    def init(state) do
        ip = Map.get(state, :ip)
        port = Map.get(state, :port)
        IO.puts "This is ip: #{inspect ip}"
        server_name = Map.get(state, :server_name)
        listener_name = Enum.join([server_name, "_control_socket"]) |> String.to_atom
        :ranch.start_listener(listener_name, 10, :ranch_tcp, [port: port, ip: ip], FtpServer, [state])
        {:ok, state}
    end
end