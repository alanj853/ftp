defmodule FtpServer do
    

use GenServer

    def start_link(socket) do
        case :ranch_tcp.recv(socket, 0, 30000) do
            {:ok, data} ->
                IO.puts("Got command #{inspect data}")
                :ranch_tcp.send(socket, "500 Bad command\r\n")
            {:error, reason} ->
                IO.puts("Got an error #{inspect reason}")
        end
        args = %{ socket: socket}
        GenServer.start_link(__MODULE__, args)
    end

    def init(state) do
        schedule_work()
        {:ok, state}
    end

    def handle_info(:work, state = %{socket: socket}) do
        # Do the desired work here

        case :ranch_tcp.recv(socket, 0, 30000) do
            {:ok, data} ->
                IO.puts("Got command #{inspect data}")
                :ranch_tcp.send(socket, "500 Bad command\r\n")
            {:error, reason} ->
                IO.puts("Got an error #{inspect reason}")
        end

        schedule_work() # Reschedule once more
        {:noreply, state}
    end

    defp schedule_work() do
        Process.send(self(), :work, []) # In 2 hours
    end
end