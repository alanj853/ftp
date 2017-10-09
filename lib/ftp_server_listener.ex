defmodule FtpServerListener do
    use GenServer

    def start_link(args) do
        GenServer.start_link(__MODULE__, args, name: @server_name)
    end

    def init(state) do
        ip = Map.get(state, :ip)
        port = Map.get(state, :port)
        :ranch.start_listener(:mylistener, 10, :ranch_tcp, [port: port, ip: ip], FtpServer, [state])
        {:ok, state}
    end
end