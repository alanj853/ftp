defmodule FtpAuth do

    def start_link(args = %{server_name: server_name}) do
        name = Enum.join([server_name, "_ftp_auth"]) |> String.to_atom
        GenServer.start_link(__MODULE__, args, name: name)
    end

    def init(state) do
        {:ok, state}
    end

    def get_state(server_name) do
        GenServer.call(server_name, :get_state)
    end

    def authenticate(server_name, username, password) do
        GenServer.call(server_name, {:authenticate, username, password})
    end

    def handle_call(:get_state, _from, state) do
        {:reply, state, state}
    end

    def handle_call({:authenticate, username, password}, _from, state = %{authentication_function: authentication_function, username: expected_username, password: expected_password}) do
        result = 
        case authentication_function do
            nil -> valid_username?(expected_username, username) && valid_password?(expected_password, password)
            _ -> true
        end
        {:reply, result, state}
    end

    @doc """
    Function to validate username
    """
    def valid_username?(expected_username, username), do: expected_username == username

    
    @doc """
    Function to validate password
    """
    def valid_password?(expected_password, password), do: expected_password == password

end