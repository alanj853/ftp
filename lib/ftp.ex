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
    `name`: A name to uniquely identify this instance of the server as `String`\n
    `ip`: An ip address as `String`\n
    `port:` The port number server will run on\n
    `root_directory`: The root directory the server will run from and display to user.\n
    `limit_viewable_dirs`: A `Struct` that contains items.\n  1. `enabled`: A `true` or `false` boolean to specify whether or not the limit_viewable_dirs option is being used.
    If this is set to `false`, then all of the directories listed as the only viewable directories will be ignored, and all directories will be viewable to the user. Default
    is `false`.\n  2. `viewable_dirs`: A `List` that contains all of the directories you would like to be available to users. Note, path needs to be given relative to the 
    `root_directory`, and not as absolute paths. E.g., given `root_directory` is "/var/system" and the path you want to specify is "/var/system/test", then 
    you would just specify it as "test".\n    2.1 Each entry into the `viewable_dirs` list should be a `Tuple` of the following format: {`directory`, `access`}, where `directory`
    is the directory name (relative to `root_directory` as mentioned above) given as a `String`, and `access` is an atom of either `:rw` or `:ro`.\n
    `username`: The username needed to log into the server. Is \"apc\" by default.\n
    `password`: The password needed to log into the server. Is \"apc\" by default.\n
    `log_file_directory`: The directory where the log file will be stored. Is \"/var/system/priv/log/ftp\" by default.\n
    `debug`: The debug level for logging. Can be either 0, 1 or 2 (default). 
            0 -> No debugging at all
            1 -> Will print messages to and from client
            2 -> Will print messages to and from client, and also all debug messages from the server backend.
    """
    def start_server(name, ip, port, root_directory, limit_viewable_dirs \\ %{enabled: false, viewable_dirs: []} , username \\ "apc", password \\ "apc", log_file_directory \\ "/var/system/priv/log/ftp", debug \\ 2) do
        ip = process_ip(ip)
        machine = get_machine_type()
        result = pre_run_checks(ip, port, root_directory, limit_viewable_dirs, log_file_directory, machine)
        case result do
            :ok_to_start -> FtpSupervisor.start_link(%{ip: ip, port: port, directory: root_directory, username: username, password: password, log_file_directory: log_file_directory, debug: debug, machine: machine, server_name: name, limit_viewable_dirs: limit_viewable_dirs})
            error -> Logger.error("NOT STARTING FTP SERVER '#{name}'. #{inspect error}")
        end
    end

    defp process_ip(ip) do
        [h1,h2,h3,h4] = String.split(ip, ".")
        {String.to_integer(h1), String.to_integer(h2), String.to_integer(h3), String.to_integer(h4)}
    end

    defp pre_run_checks(ip, port, root_directory, limit_viewable_dirs, log_file_directory, machine) do
        cond do
            ( File.exists?(root_directory) == false ) -> "#{inspect root_directory} does not exist"
            ( File.dir?(root_directory) == false ) -> "#{inspect root_directory} exists but it is not a directory"
            ( File.exists?(log_file_directory) == false ) && ( machine == :nmc3 ) -> "#{inspect log_file_directory} does not exist"
            ( is_read_only_dir(root_directory) == true ) && ( machine == :nmc3 ) -> "#{inspect root_directory}  is part of the RO filesystem"
            ( is_read_only_dir(log_file_directory) == true ) && ( machine == :nmc3 ) -> "#{inspect log_file_directory} is part of the RO filesystem"
            ( Map.get(limit_viewable_dirs, :enabled) == true ) && ( valid_viewable_dirs(root_directory , Map.get(limit_viewable_dirs, :viewable_dirs)) == false ) -> "Invalid viewable directories listed"
            true -> :ok_to_start   
        end
    end

    defp get_machine_type() do
        case System.get_env("HOME") do
            "/root" -> :nmc3
            _ -> :desktop
        end
    end

    def valid_viewable_dirs(rootdir, viewable_dirs) do
        Process.put(:valid_view_able_dirs, true)
        result =
        for item <- viewable_dirs do
            dir = elem(item, 0)
            path = Path.join([rootdir, dir])
            case File.exists?(path) do
                true ->
                    :ok
                false -> 
                    Logger.error("Viewable dir: #{path} does not exist.")
                    Process.put(:valid_view_able_dirs, false)
                    :error
            end
        end
        Process.get(:valid_view_able_dirs)   
    end

    def is_read_only_dir(path) do
        case (path == String.trim_leading(path, "/var/system")) do
            true -> true
            false -> false
        end
    end

    def sample() do
        limit_viewable_dirs = %{
            enabled: true,
            viewable_dirs: [
                {"fw", :rw},
                {"waveforms", :ro}
            ]
        }
        start_server("uc1", "127.0.0.1", 2121, "/home/user/var/system/priv/input", limit_viewable_dirs)
    end
     
    
end