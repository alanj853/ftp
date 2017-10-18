defmodule FtpSupervisor do
    use Supervisor

    def start_link(args) do
        result = {:ok, sup} = Supervisor.start_link(__MODULE__, [])
        start_workers(sup, args)
        result
    end

    def start_workers(supervisor, args=%{ip: ip, port: port, directory: root_directory, username: username, password: password}) do
        ro_dirs = []
        rw_dirs = []
        other_config = %{ro_dirs: ro_dirs, rw_dir: rw_dirs}
        {:ok, ftp_data_pid} = Supervisor.start_child(supervisor, worker(FtpData, []))
        {:ok, ftp_logger_pid} = Supervisor.start_child(supervisor, worker(FtpLogger, [%{debug: 2}]))
        {:ok, ftp_sub_sup_pid} = Supervisor.start_child(supervisor, supervisor(FtpSubSupervisor, [%{ftp_logger_pid: ftp_logger_pid, ftp_data_pid: ftp_data_pid, root_dir: root_directory, username: username, password: password, ip: ip, port: port, debug: 2, timeout: :infinity, restart_time: 500}]))
    end

    def init(_) do
        supervise [], strategy: :one_for_one
    end
end