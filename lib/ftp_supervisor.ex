defmodule FtpSupervisor do
    use Supervisor

    def start_link do
        result = {:ok, sup} = Supervisor.start_link(__MODULE__, [])
        start_workers(sup)
        result
    end

    def start_workers(supervisor) do
        {:ok, ftp_data_pid} = Supervisor.start_child(supervisor, worker(FtpData, []))
        {:ok, ftp_info_pid} = Supervisor.start_child(supervisor, worker(FtpInfo, ["/home/user/var/system"]))
        {:ok, ftp_sub_sup_pid} = Supervisor.start_child(supervisor, supervisor(FtpSubSupervisor, [%{ftp_data_pid: ftp_data_pid, ftp_info_pid: ftp_info_pid, root_dir: "/home/user/var/system"}]))
    end

    def init(_) do
        supervise [], strategy: :one_for_one
    end
end