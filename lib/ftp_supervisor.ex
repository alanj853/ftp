defmodule FtpSupervisor do
    use Supervisor

    def start_link(args) do
        result = {:ok, sup} = Supervisor.start_link(__MODULE__, [])
        start_workers(sup, args)
        result
    end

    def start_workers(supervisor, args=%{ip: ip, port: port, directory: root_directory, username: username, password: password}) do
        {:ok, ftp_data_pid} = Supervisor.start_child(supervisor, worker(FtpData, []))
        {:ok, ftp_info_pid} = Supervisor.start_child(supervisor, worker(FtpInfo, [root_directory]))
        {:ok, ftp_sub_sup_pid} = Supervisor.start_child(supervisor, supervisor(FtpSubSupervisor, [%{ftp_data_pid: ftp_data_pid, ftp_info_pid: ftp_info_pid, root_dir: root_directory, username: username, password: password, ip: ip, port: port}]))
    end

    def init(_) do
        supervise [], strategy: :one_for_one
    end
end