defmodule FtpSupervisor do
    @moduledoc """
    Documentation for the FtpSupervisor. Module is used to start and supervise 
    the FtpData and FtpLogger `GenServer`s and also the FtpSubSupervisor `Supervisor`
    """
    require Logger
    use Supervisor

    
    def start_link(args) do
        server_name = Map.get(args, :server_name)
        name = Enum.join([server_name, "_ftp_supervisor"]) |> String.to_atom
        result = 
        case Supervisor.start_link(__MODULE__, [], name: name) do
            {:ok, sup} ->
                start_workers(sup, args)
                {:ok, sup}
            {:error, {:already_started, pid}} ->
                Logger.info("Could not start FTP Server #{name}: {:already_started #{inspect pid}}")
                {:ok, pid}
            {:error, error} ->
                Logger.info("Could not start FTP Server #{name}: #{inspect error}")
                {:ok, nil}
        end
        result
    end

    
    def start_workers(supervisor, _args=%{ip: ip, port: port, directory: root_directory, log_file_directory: log_file_directory, debug: debug, machine: machine, username: username, password: password, server_name: server_name, limit_viewable_dirs: limit_viewable_dirs}) do
        {:ok, ftp_data_pid} = Supervisor.start_child(supervisor, worker(FtpData, [%{server_name: server_name}]))
        {:ok, ftp_logger_pid} = Supervisor.start_child(supervisor, worker(FtpLogger, [%{debug: debug, log_file_directory: log_file_directory, machine: machine, server_name: server_name}]))
        {:ok, _ftp_sub_sup_pid} = Supervisor.start_child(supervisor, supervisor(FtpSubSupervisor, [%{ftp_logger_pid: ftp_logger_pid, ftp_data_pid: ftp_data_pid, root_dir: root_directory, username: username, password: password, ip: ip, port: port, debug: debug, timeout: :infinity, restart_time: 500, server_name: server_name, limit_viewable_dirs: limit_viewable_dirs}]))
    end

    
    def init(_) do
        supervise [], strategy: :one_for_one
    end
end