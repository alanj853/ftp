defmodule FtpSubSupervisor do
    use Supervisor

    def start_link(state) do
        {:ok, pid} = Supervisor.start_link(__MODULE__, state)
    end

    def init(state) do
        child_process = [ worker(FtpServerListener, [state])]
        supervise child_process, strategy: :one_for_one
    end
end