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
        Supervisor.start_link(__MODULE__, [], name: name)
    end


    def init(_) do
      spec = {:bifrost,
        {:bifrost, :start_link, [Ftp.Bifrost,
                                 [{:port, 2525}]]},
        :permanent,
        5000,
        :worker,
        [:bifrost]}

        supervise [spec], strategy: :one_for_one
    end
end
