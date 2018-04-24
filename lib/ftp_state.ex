defmodule FtpState do
    @moduledoc """
    The module is used to store the FTP Servers State so that it is easily accessible from
    all modules.
    """

    use GenServer
    def start_link(server_name) do
        GenServer.start_link(__MODULE__, server_name, name: __MODULE__)
    end

    
    def init(name) do
        :ets.new(name, [:set, :public, :named_table]) ## create new ets database
        {:ok, %{db_name: name}}
    end

    def get(key), do: GenServer.call(__MODULE__, {:get, key})

    def get_all(server=:all_servers), do: GenServer.call(__MODULE__, {:get_all, :all_servers})

    def get_all(server \\ nil), do: GenServer.call(__MODULE__, {:get_all, server})

    def set(key, value, from \\ nil), do: GenServer.call(__MODULE__, {:set, key, value, from})

    # def handle_call({:get, key}, _from, state = %{db_name: name}) do
    #     result = :ets.lookup(name, key)[key] ## get `key` from the returned `Keyword` list
    #     {:reply, result, state}
    # end

    def handle_call({:get, key}, from, state) do
        caller = get_caller_name(from)
        result = Map.get(state, caller) |> Map.get(key)
        {:reply, result, state}
    end

    def handle_call({:get_all, :all_servers}, from, state = %{db_name: name}) do
        {:reply, state, state}
    end

    def handle_call({:get_all, nil}, from, state = %{db_name: name}) do
        caller = get_caller_name(from)
        IO.puts "Getting all for #{inspect caller}"
        server_state = Map.get(state, caller)
        {:reply, server_state, state}
    end

    def handle_call({:get_all, server}, from, state = %{db_name: name}) do
        IO.puts "Getting all for #{inspect server}"
        server_state = Map.get(state, server)
        {:reply, server_state, state}
    end

    def handle_call({:set, key, value, nil}, from, state = %{db_name: name}) do
        caller = get_caller_name(from)
        old_caller_state = 
        case Map.get(state, caller) do
            nil -> %{}
            map -> map
        end
        new_caller_state = Map.put(old_caller_state, key, value)
        new_state = Map.put(state, caller, new_caller_state)
        {:reply, :ok, new_state}
    end

    def handle_call({:set, key, value, caller}, _from, state = %{db_name: name}) do
        old_caller_state = 
        case Map.get(state, caller) do
            nil -> %{}
            map -> map
        end
        new_caller_state = Map.put(old_caller_state, key, value)
        new_state = Map.put(state, caller, new_caller_state)
        {:reply, :ok, new_state}
    end

    defp get_caller_name({caller, _ref}) do
        caller = Process.info(caller)[:registered_name] |> to_string()
        IO.puts "Thhis is caller: #{inspect caller}"
        caller =
            caller
            |> String.trim_trailing("_ftp_active_socket")
            |> String.trim_trailing("_ftp_auth")
            |> String.trim_trailing("_ftp_data")
            |> String.trim_trailing("_ftp_logger")
            |> String.trim_trailing("_ftp_pasv_socket")
            |> String.trim_trailing("_ftp_server_listener")
            |> String.trim_trailing("_ftp_server")
            |> String.trim_trailing("_ftp_sub_supervisor")
            |> String.trim_trailing("_ftp_supervisor")
            |> String.to_atom        
    end


    # def handle_call({:set, key, value}, _from, state = %{db_name: name}) do
    #     result = :ets.insert(name, {key, value})
    #     {:reply, result, state}
    # end
  end