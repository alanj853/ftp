defmodule FtpInfo do
    @moduledoc """
    Documentation for Ftp.
    """
   
    @server_name __MODULE__
    @debug true
    require Logger
    use GenServer
    
    def start_link(root_dir) do
      initial_state = %{root_dir: root_dir, server_cd: root_dir ,client_cd: "/", data_socket: nil, data_ip: nil, data_port: nil, type: nil, offset: 0}
      GenServer.start_link(__MODULE__, initial_state, name: @server_name)
    end
  
    def init(state) do
      {:ok, state}
    end
  
    def get_state(pid) do
      GenServer.call pid, :get_state
    end
  
    def set_state(pid, state) do
      GenServer.call __MODULE__, {:set_state, state}
    end
  
    def handle_call(:get_state, _from, state) do
      #IO.puts "This is call: #{inspect from}"
      
      {:reply, state, state}
    end

    def handle_info({:set_server_state, new_state}, state) do
      FtpServer.set_state(new_state)
      {:noreply, state}
  end
  
    def handle_call({:set_state, new_state}, _from, state=%{root_dir: root_dir, server_cd: server_cd , client_cd: client_cd, data_ip: ip, data_port: port, type: type, offset: offset}) do
      {:reply, state, new_state}
    end
    
end
  