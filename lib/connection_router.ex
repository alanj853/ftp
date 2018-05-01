defmodule ConnectionRouter do
    use DynamicSupervisor

    def start_link(socket) do
        DynamicSupervisor.start_link(__MODULE__, [], name: name(socket))
    end
    
    def init(_args) do
        DynamicSupervisor.init(strategy: :one_for_one)
    end

    def start_all(socket) do
        DynamicSupervisor.start_child(name(socket), {FtpData, [%{server_name: :foo}]})
    end
    
    def name(socket) do
        {:via, Registry, {AcceptorRegistry, {__MODULE__, socket}}}
    end
end