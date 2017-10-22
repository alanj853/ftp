defmodule Ftp do
    require Logger
    @moduledoc """
    Module where the ftp server is started from
    """

    ## Uncomment the lines below to run this as an application from running `iex -S mix`

    #use Application

    # def start(_type, _args)  do
    #     start_server("127.0.0.1", 2121, "/home/user/var/system", "user1", "user1")
    # end


    @doc """
    Function to start the server.\n
    `ip`: An ip address as `String`\n
    `port:` The port number server will run on\n
    `root_directory`: The root directory the server will run from and display to user.\n
    `username`: The username needed to log into the server. Is \"apc\" by default.\n
    `password`: The password needed to log into the server. Is \"apc\" by default.\n
    `log_file_directory`: The directory where the log file will be stored. Is \"/var/system/priv/log/ftp\" by default.\n
    `debug`: The debug level for logging. Can be either 0, 1 or 2 (default). 
            0 -> No debugging at all
            1 -> Will print messages to and from client
            2 -> Will print messages to and from client, and also all debug messages from the server backend.
    """
    def start_server(name, ip, port, root_directory, username \\ "apc", password \\ "apc", log_file_directory \\ "/var/system/priv/log/ftp", debug \\ 2) do
        ip = process_ip(ip)
        machine = get_machine_type()
        result = pre_run_checks(ip, port, root_directory, log_file_directory, machine)
        case result do
            :ok_to_start -> FtpSupervisor.start_link(%{ip: ip, port: port, directory: root_directory, username: username, password: password, log_file_directory: log_file_directory, debug: debug, machine: machine, server_name: name})
            error -> Logger.error("NOT STARTING FTP SERVER. #{inspect error}")
        end
    end

    defp process_ip(ip) do
        [h1,h2,h3,h4] = String.split(ip, ".")
        {String.to_integer(h1), String.to_integer(h2), String.to_integer(h3), String.to_integer(h4)}
    end

    defp pre_run_checks(ip, port, root_directory, log_file_directory, machine) do
        cond do
            ( File.exists?(root_directory) == false ) -> "#{inspect root_directory} does not exist"
            ( File.dir?(root_directory) == false ) -> "#{inspect root_directory} exists but it is not a directory"
            ( File.exists?(log_file_directory) == false ) && (machine == :nmc3) -> "#{inspect log_file_directory} does not exist"
            ( is_read_only_dir(root_directory) == true ) && (machine == :nmc3) -> "#{inspect root_directory}  is part of the RO filesystem"
            ( is_read_only_dir(log_file_directory) == true ) && (machine == :nmc3) -> "#{inspect log_file_directory} is part of the RO filesystem"
            true -> :ok_to_start   
        end
    end

    defp get_machine_type() do
        case System.get_env("HOME") do
            "/root" -> :nmc3
            _ -> :desktop
        end
    end

    def is_read_only_dir(path) do
        case (path == String.trim_leading(path, "/var/system")) do
            true -> true
            false -> false
        end
    end

    def dummy() do
        start_server("uc1", "127.0.0.1", 2121, "/home/user")
        #start_server("uc2", "127.0.0.1", 2122, "/home/user")
    end
     
    
end