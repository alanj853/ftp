defmodule FtpSubSupervisor do
    use Supervisor

    def start_link(state) do
        {:ok, _pid} = Supervisor.start_link(__MODULE__, state)
    end

    def init(state) do
        Process.put(:default_state, state)
        child_process = 
        [ 
            worker(FtpServerListener, [state])
        ]
        Process.put(:child_process, child_process)
        supervise(child_process, strategy: :one_for_one)
    end

end