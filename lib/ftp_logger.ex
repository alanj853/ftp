defmodule FtpLogger do
    @moduledoc """
    Documentation for FtpServer
    """

    @server_name FtpLogger
    @debug 2
    require Logger
    use GenServer

    def start_link(args = %{debug: debug}) do
        {:ok, pid} = GenServer.start_link(__MODULE__, debug)
    end

    def init(state) do
        Logger.info "Started Logger"
        {:ok, state}
    end

    def handle_info({:ftp_server_log_message, message}, state = debug) do
        case debug do
            0 -> :ok
            _ -> Logger.debug(message)
        end
        {:noreply, state}
    end

end
