defmodule FtpInfo do
    @moduledoc """
    Documentation for Ftp.
    """
   
    @server_name __MODULE__
    @debug true
    require Logger
    use GenServer
    
    def start(root_dir) do
      initial_state = %{root_dir: root_dir, server_cd: root_dir ,client_cd: "/", data_ip: nil, data_port: nil, type: nil }
      GenServer.start_link(__MODULE__, initial_state, name: @server_name)
    end
  
    def init(state) do
      {:ok, state}
    end
  
    def get_state() do
      GenServer.call __MODULE__, :get_state
    end
  
    def set_state(state) do
      GenServer.call __MODULE__, {:set_state, state}
    end
  
    def handle_call(:get_state, _from, state=%{root_dir: root_dir, server_cd: server_cd , client_cd: client_cd, data_ip: ip, data_port: port, type: type }) do
      {:reply, state, state}
    end
  
    def handle_call({:set_state, new_state}, _from, state=%{root_dir: root_dir, server_cd: server_cd , client_cd: client_cd, data_ip: ip, data_port: port, type: type }) do
      {:reply, state, new_state}
    end
    
end
  