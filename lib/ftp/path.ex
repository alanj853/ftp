defmodule Ftp.Path do
  @doc """
  Function to determine if `path` is absolute
  """
  require Logger

  def is_absolute_path(path) do
    path == String.trim_leading(path, "/")
  end

  @doc """
  Function to determine the path as it is on the filesystem, given the `root_directory` on the ftp server, `current_directory`
  (as the client sees it) and the `path` provided by the client.
  """
  def determine_path(root_directory, current_directory, path) do
    ## check if path given is an absolute path
    new_path =
      case is_absolute_path(path) do
        true ->
          String.trim_leading(path, "/") |> Path.expand(root_directory)

        false ->
          String.trim_leading(path, "/")
          |> Path.expand(current_directory)
          |> String.trim_leading("/")
          |> Path.expand(root_directory)
      end

    Logger.debug(
      "This is the path we were given: '#{path}'. This is current_directory: '#{current_directory}'. This is root_directory: '#{
        root_directory
      }'. Determined that this is the current path: '#{new_path}'"
    )

    new_path
  end
end
