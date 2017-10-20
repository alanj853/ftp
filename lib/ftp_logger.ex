defmodule FtpLogger do
    @moduledoc """
    Documentation for FtpServer
    """

    @server_name __MODULE__
    @desktop_logfile "lib/ftp_log.txt"
    require Logger
    use GenServer

    def start_link(_args = %{debug: debug, log_file_directory: dir, machine: machine}) do
        dir = String.trim_trailing(dir, "/")
        log_file = Enum.join([dir, "/ftp_log.txt"])
        {:ok, _pid} = GenServer.start_link(__MODULE__, %{debug: debug, log_file: log_file, machine: machine})
    end

    def init(state = %{debug: _debug, log_file: log_file, machine: machine}) do
        Logger.info "Started Logger"
        case machine do ## check to see if we're on a Desktop
            :desktop -> 
                Logger.info("We're on a desktop. Every debug message will be logged with Logger.debug and also logged to #{inspect @desktop_logfile}")
                log_file_bak = String.trim_trailing(@desktop_logfile, ".txt")
                log_file_bak = Enum.join([log_file_bak, "_bak.txt"])
                case File.exists?(@desktop_logfile) do
                    true -> File.copy(@desktop_logfile, log_file_bak )
                    false -> :ok
                end
            other_machine -> 
                Logger.info("We're on an #{inspect other_machine}. Every debug message will be logged with Logger.info and also logged to #{inspect log_file}")
                log_file_bak = String.trim_trailing(log_file, ".txt")
                log_file_bak = Enum.join([log_file_bak, "_bak.txt"])
                case File.exists?(log_file) do
                    true -> File.copy(log_file, log_file_bak )
                    false -> :ok
                end
        end
        {:ok, state}
    end

    def handle_info({:ftp_server_log_message, message, priority}, state = %{debug: debug, log_file: log_file, machine: machine}) do
        case debug do
            0 -> 
                :ok
            1 -> ## only log messages of priority `:comm`
                case priority do
                    :comm -> log_message(message, log_file, machine)
                    _ -> :ok
                end
            2 ->
                log_message(message, log_file, machine)
        end
        {:noreply, state}
    end

    defp log_message(message, log_file, machine) do
        case machine do
            :desktop -> 
                Logger.debug(message)
                message = String.trim_trailing(message, "\n")
                timestamp = DateTime.utc_now |> DateTime.to_string
                File.write(@desktop_logfile, Enum.join([timestamp, "  " , message, "\n"]), [:append])
            other_machine -> 
                Logger.info(message)
                message = String.trim_trailing(message, "\n")
                timestamp = DateTime.utc_now |> DateTime.to_string
                File.write(log_file, Enum.join([timestamp, "  " , message, "\n"]), [:append])
        end
    end

end
