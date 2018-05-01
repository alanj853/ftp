defmodule FtpSupervisor do
    @moduledoc """
    Documentation for the FtpSupervisor. Module is used to start and supervise 
    the FtpData and FtpLogger `GenServer`s and also the FtpSubSupervisor `Supervisor`
    """
    require Logger
    use Supervisor

    
    def start_link(args) do
        server_name = Map.get(args, :server_name)
        FtpState.start_link(server_name)
        # FtpState.set(:server_name, server_name)
        name = Enum.join([server_name, "_ftp_supervisor"]) |> String.to_atom
        result = 
        case Supervisor.start_link(__MODULE__, [], name: name) do
            {:ok, sup} ->
                start_workers(sup, args)
                {:ok, sup}
            {:error, {:already_started, pid}} ->
                Logger.info("Could not start FTP Server #{name}: {:already_started #{inspect pid}}")
                {:ok, pid}
            {:error, error} ->
                Logger.info("Could not start FTP Server #{name}: #{inspect error}")
                {:ok, nil}
        end
        result
    end

    
    def start_workers(supervisor, args = %{server_name: server_name}) do
        for {key, val} <- args, do: FtpState.set(key, val, server_name)
        
        {:ok, ftp_data_pid} = Supervisor.start_child(supervisor, worker(FtpData, [%{server_name: server_name}]))
        {:ok, ftp_logger_pid} = Supervisor.start_child(supervisor, worker(FtpLogger, [%{server_name: server_name}]))
        {:ok, ftp_auth_pid} = Supervisor.start_child(supervisor, supervisor(FtpAuth, [%{server_name: server_name}]))
        {:ok, ftp_sub_sup_pid} = Supervisor.start_child(supervisor, supervisor(FtpSubSupervisor, [%{server_name: server_name}]))

        FtpState.set(:ftp_data_pid, ftp_data_pid, server_name)
        FtpState.set(:ftp_logger_pid, ftp_logger_pid, server_name)
        FtpState.set(:ftp_auth_pid, ftp_auth_pid, server_name)
        FtpState.set(:ftp_sub_sup_pid, ftp_sub_sup_pid, server_name)

    end

    
    def init(_) do
        supervise [], strategy: :one_for_all
    end
end