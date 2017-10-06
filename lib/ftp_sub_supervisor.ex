defmodule FtpSubSupervisor do
    use Supervisor

    def start_link(state = %{ftp_data_pid: ftp_data_pid, ftp_info_pid: ftp_info_pid, root_dir: root_dir}) do
        {:ok, pid} = Supervisor.start_link(__MODULE__, state)
    end

    def init(state) do
        child_process = [ worker(FtpServer, [state])]
        supervise child_process, strategy: :one_for_one
    end
end