defmodule FtpAuth do
    @moduledoc """
    Module to handle Authentication for the FTP Server. The actual authenication is handled
    elsewhere in another module of the user's choosing. When starting this GenServer, the user
    passes in an authenication function that takes 2 parameters, where the first is the username
    and the second is the password, both as `String`s. If the user does not supply an authentication
    function, then the FTP server will use the username and password that were given when calling the 
    `Ftp.start_server` as the credentials, and will compare those with any credentials an FTP client provides.
    """

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

    def handle_call({:authenticate, username, password}, _from, state = %{authentication_function: nil, username: expected_username, password: expected_password}) do
        {:reply, valid_username?(expected_username, username) && valid_password?(expected_password, password), state}
    end
    
    @doc """
    Currently just support JWT authenication
    """
    def handle_call({:authenticate, username, password}, _from, state = %{authentication_function: authentication_function}) do
        result =
        case authentication_function.(username, password) do
            {:ok, _jwt, _user} -> true
            {:error, :invalid_password} -> false
            _some_other_authentication_method -> false ## will remove this when we support more than one external authentication method
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