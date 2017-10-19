defmodule FtpLogger do
    @moduledoc """
    Documentation for FtpServer
    """

    @server_name FtpLogger
    @debug 2
    @logfile "/home/alan/Development/ftp/lib/ftp_log.txt"
    @logfile_bak "/home/alan/Development/ftp/lib/ftp_log1.txt"
    require Logger
    use GenServer

    def start_link(args = %{debug: debug}) do
        {:ok, pid} = GenServer.start_link(__MODULE__, debug)
    end

    def init(state) do
        Logger.info "Started Logger"
        case System.get_env("HOME") do
            "/root" -> 
                Logger.info("We're on an NMC3. Every debug message will be logged with Logger.info")
            _ -> 
                Logger.info("We're NOT on an NMC3. Every debug message will be logged with Logger.debug")
                File.copy(@logfile, @logfile_bak )
        end
        {:ok, state}
    end

    def handle_info({:ftp_server_log_message, message}, state = debug) do
        case debug do
            0 -> :ok
            _ ->
                case System.get_env("HOME") do
                    "/root" -> Logger.info(message)
                    _ -> 
                        Logger.debug(message)
                        message = String.trim_trailing(message, "\n")
                        timestamp = DateTime.utc_now |> DateTime.to_string
                        File.write(@logfile, Enum.join([timestamp, "  " , message, "\n"]), [:append])
                end
        end
        {:noreply, state}
    end

end
