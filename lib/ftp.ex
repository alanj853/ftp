defmodule Ftp do
    @moduledoc """
    Module where the ftp server is started from
    """

    ## Uncomment the lines below to run this as an application from running `iex -S mix`

    #use Application

    # def start(_type, _args)  do
    #     start_server("127.0.0.1", 2121, "/home/user/var/system", "user1", "user1")
    # end


    @doc """
    Function to start the server.
    `ip`: An ip address as `String`
    `port:` The port number server will run on
    `root_directory`: The root directory the server will run from and display to user.
    `username`: The username needed to log into the server. Is \"apc\" by default.
    `password`: The password needed to log into the server. Is \"apc\" by default.
    """
    def start_server(ip, port, root_directory, username \\ "apc", password \\ "apc") do
        ip = process_ip(ip)
        FtpSupervisor.start_link(%{ip: ip, port: port, directory: root_directory, username: username, password: password})
    end

    defp process_ip(ip) do
        [h1,h2,h3,h4] = String.split(ip, ".")
        {String.to_integer(h1), String.to_integer(h2), String.to_integer(h3), String.to_integer(h4)}
    end
    
end