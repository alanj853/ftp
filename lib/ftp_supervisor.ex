defmodule FtpSupervisor do
    use Supervisor

    def start_link(args) do
        result = {:ok, sup} = Supervisor.start_link(__MODULE__, [])
        start_workers(sup, args)
        result
    end

    def start_workers(supervisor, _args=%{ip: ip, port: port, directory: root_directory, log_file_directory: log_file_directory, debug: debug, machine: machine, username: username, password: password}) do
        ro_dirs = []
        rw_dirs = []
        _other_config = %{ro_dirs: ro_dirs, rw_dir: rw_dirs}
        {:ok, ftp_data_pid} = Supervisor.start_child(supervisor, worker(FtpData, []))
        {:ok, ftp_logger_pid} = Supervisor.start_child(supervisor, worker(FtpLogger, [%{debug: debug, log_file_directory: log_file_directory, machine: machine}]))
        {:ok, _ftp_sub_sup_pid} = Supervisor.start_child(supervisor, supervisor(FtpSubSupervisor, [%{ftp_logger_pid: ftp_logger_pid, ftp_data_pid: ftp_data_pid, root_dir: root_directory, username: username, password: password, ip: ip, port: port, debug: debug, timeout: :infinity, restart_time: 500}]))
    end

    def init(_) do
        supervise [], strategy: :one_for_one
    end
end