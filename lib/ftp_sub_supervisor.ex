defmodule FtpSubSupervisor do
    use Supervisor

    def start_link(state) do
        server_name = Map.get(state, :server_name)
        name = Enum.join([server_name, "_ftp_sub_supervisor"]) |> String.to_atom
        {:ok, _pid} = Supervisor.start_link(__MODULE__, state, name: name)
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