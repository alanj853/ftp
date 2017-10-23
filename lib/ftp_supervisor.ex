defmodule FtpSupervisor do
    use Supervisor

    def start_link(args) do
        server_name = Map.get(args, :server_name)
        name = Enum.join([server_name, "_ftp_supervisor"]) |> String.to_atom
        result = {:ok, sup} = Supervisor.start_link(__MODULE__, [], name: name)
        start_workers(sup, args)
        result
    end

    def start_workers(supervisor, _args=%{ip: ip, port: port, directory: root_directory, log_file_directory: log_file_directory, debug: debug, machine: machine, username: username, password: password, server_name: server_name, limit_viewable_dirs: limit_viewable_dirs}) do
        ro_dirs = []
        rw_dirs = []
        _other_config = %{ro_dirs: ro_dirs, rw_dir: rw_dirs}
        {:ok, ftp_data_pid} = Supervisor.start_child(supervisor, worker(FtpData, [%{server_name: server_name}]))
        {:ok, ftp_logger_pid} = Supervisor.start_child(supervisor, worker(FtpLogger, [%{debug: debug, log_file_directory: log_file_directory, machine: machine, server_name: server_name}]))
        {:ok, _ftp_sub_sup_pid} = Supervisor.start_child(supervisor, supervisor(FtpSubSupervisor, [%{ftp_logger_pid: ftp_logger_pid, ftp_data_pid: ftp_data_pid, root_dir: root_directory, username: username, password: password, ip: ip, port: port, debug: debug, timeout: :infinity, restart_time: 500, server_name: server_name, limit_viewable_dirs: limit_viewable_dirs}]))
    end

    def init(_) do
        supervise [], strategy: :one_for_one
    end
end