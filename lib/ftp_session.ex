defmodule FtpSession do
  @moduledoc """
  Documentation for Ftp.
  """
 
  @server_name __MODULE__
  require Logger
  use GenServer
  #@behaviour GenServer
  #@behaviour MyBehaviour

  # @default_state %{ 
  #   connection_status: :not_connected,
  #   current_directory: "/",
  # }

  def start(status) do
    initial_state = %{ connection_status: status, current_directory: "/", response: "" }
    GenServer.start_link(__MODULE__, initial_state, name: @server_name)
  end

  def init(state=%{connection_status: status, current_directory: cd, response: response}) do
    Logger.info "Session Started."
    {:ok, state}
  end

  def list_files() do
    GenServer.call __MODULE__, {:list_files, nil}
  end

  def list_files(path) do
    GenServer.call __MODULE__, {:list_files, path}
  end

  def current_directory() do
    GenServer.call __MODULE__, :current_directory
  end

  def change_directory(path) do
    GenServer.call __MODULE__, {:change_directory, path}
  end

  def handle_call({:list_files, path}, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    new_response = ""
    
    path = case path do
      nil -> cd
      "" -> cd
      _ -> path 
    end

    new_response = case allowed_to_view(path) do
      true ->
        Logger.info "Listing files in path '#{path}'"
        case File.ls(path) do
          {:ok, files} ->
            sorted_files = Enum.sort(files)
            for  file  <-  sorted_files  do
            end
            files_as_string = Enum.join(sorted_files, " ")
            Logger.info "Files Found: #{files_as_string}"
            files_as_string
          {:error, reason} ->
            Logger.info "ls command failed. Reason: #{inspect reason}"
            to_string(reason)
        end
      false ->
        Logger.info "You don't have permission to view this file/folder."
        "You don't have permission to view this file/folder."
      end


    new_state=%{connection_status: status, current_directory: cd, response: new_response}
    {:reply, state, new_state}
  end

  
  def handle_call(:current_directory, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    Logger.debug "cd: #{inspect cd}"
    new_response = cd
    new_state=%{connection_status: status, current_directory: cd, response: new_response}
    {:reply, state, new_state}
  end

  def handle_call({:change_directory, path}, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    new_path = cd
    new_path = case File.dir?(path) do
      true ->
        path
      false ->
        Logger.debug "Current path '#{path}' does not exist."
        cd
    end
    Logger.debug "Current Directory: #{path}"
    new_state = %{connection_status: status, current_directory: new_path, response: new_path}
    {:reply, state, new_state}
  end

  defp allowed_to_view(path) do
    ro_dirs = Application.get_env(:ftp, :ro_dirs)
    rw_dirs = Application.get_env(:ftp, :rw_dirs)
    
    true
  end











  
  # def change_directory(state=%{connection_status: status, current_directory: cd}, path) do
  #   new_path = cd
  #   new_path = case File.dir?(path) do
  #     true ->
  #       path
  #     false ->
  #       Logger.debug "Current path '#{path}' does not exist."
  #       cd
  #   end
  #   Logger.debug "Current Directory: #{path}"
  #   %{connection_status: status, current_directory: new_path}
  # end

  

  # def login(state=%{connection_status: status, current_directory: cd}, user_name, password) do
  #   case status do
  #     :connected -> Logger.info "Already Logged in"
  #     _ -> attempt_login(user_name, password)
  #   end
  # end

  # def make_directory(state=%{connection_status: status, current_directory: cd}, path) do
  #   case File.mkdir_p(path) do
  #     :ok ->
  #       Logger.info "Directory #{path} created."
  #     {:error, reason} ->
  #       Logger.info "Directory #{path} could not be created."
  #       Logger.info "#{inspect reason}"
  #   end
  #   state=%{connection_status: status, current_directory: cd}
  # end

  # def list_files(state=%{connection_status: status, current_directory: cd}, path) do
  #   case File.ls(path) do
  #     {:ok, files} ->
  #       sorted_files = Enum.sort(files)
  #       for  file  <-  sorted_files  do
  #         IO.puts "#{file}"
  #       end
  #     {:error, reason} ->
  #       Logger.info "ls command failed. Reason: #{inspect reason}"
  #   end
  #   state=%{connection_status: status, current_directory: cd}
  # end

  # def remove_directory(state=%{connection_status: status, current_directory: cd}, path) do
  #   case File.rm_rf(path) do
  #     {:ok, _} ->
  #       Logger.info "Directory #{path} removed."
  #     {:error, reason, file} ->
  #       Logger.info "Error removing directory '#{path}'"
  #       Logger.info "Error removing #{file} from #{path} . Reason: #{inspect reason}"
  #   end
  #   state=%{connection_status: status, current_directory: cd}
  # end

  # def remove_file(state=%{connection_status: status, current_directory: cd}, path) do
  #   case File.rm(path) do
  #     {:ok, _} ->
  #       Logger.info "File #{path} removed."
  #     {:error, reason} ->
  #       Logger.info "Error removing file '#{path}'. Reason: #{inspect reason}"
  #   end
  #   state=%{connection_status: status, current_directory: cd}
  # end

  # def rename_file(state=%{connection_status: status, current_directory: cd}, from_path, to_path) do
  #   case File.rename(from_path, to_path) do
  #     :ok ->
  #       Logger.info "File '#{from_path}' renamed to '#{to_path}'."
  #     {:error, reason} ->
  #       Logger.info "Error renaming file '#{from_path}' to '#{to_path}'. Reason: #{inspect reason}"
  #   end
  #   state=%{connection_status: status, current_directory: cd}
  # end

  # def file_info(state=%{connection_status: status, current_directory: cd}, path) do
  #   file_info = case File.stat(path) do
  #     {:ok, info} ->
  #       analyse_file_info(info, path)
  #     {:error, reason} ->
  #       Logger.info "Error retrieving information on file '#{path}'. Reason: #{inspect reason}"
  #       err = "Error retrieving information on file '#{path}'. Reason: #{inspect reason}"  
  #   end
  #   file_info
  # end

  # {init, 2}, % State, PropList (options) -> State
  # {login, 3}, % State, Username, Password -> {true OR false, State}
  # DONE {current_directory, 1}, % State -> Path
  # DONE {make_directory, 2}, % State, Path -> State Change
  # DONE {change_directory, 2}, % State, Path -> State Change
  # DONE {list_files, 2}, % State, Path -> [FileInfo] OR {error, State}
  # DONE {remove_directory, 2}, % State, Path -> State Change
  # DONE {remove_file, 2}, % State, Path -> State Change
  # {put_file, 4}, % State, File Name, (append OR write), Fun(Byte Count) -> State Change
  # {get_file, 2}, % State, Path -> {ok, Fun(Byte Count)} OR error
  # DONE {file_info, 2}, % State, Path -> {ok, FileInfo} OR {error, ErrorCause}
  # DONE {rename_file, 3}, % State, From Path, To Path -> State Change
  # {site_command, 3}, % State, Command Name String, Command Args String -> State Change
  # {site_help, 1}, % State -> {ok, [HelpInfo]} OR {error, State}
  # {disconnect, 1}]; % State -> State Change
  
  # defp analyse_file_info(info, path) do
    
  #   access = case info.access do
  #     :read -> "RO"
  #     :write -> "WO"
  #     :read_write -> "RW"
  #     :none -> "NONE"
  #   end

  #   uid = info.uid
  #   gid = info.gid
  #   size = info.size
  #   {{year, month, day}, {hour, min, second }} = info.mtime
  #   time = [to_string(year), "/", to_string(month), "/", to_string(day), "_", to_string(hour), ":", to_string(min), ":", to_string(second)]
  #   |>
  #     Enum.join

  #   [access, " ", to_string(uid), ":", to_string(gid), " ", to_string(size), " Bytes ", time, " ", path]
  #   |>
  #     Enum.join
  # end

  # defp attempt_login(user_name, password) do
  #   expected_user_name = "apc"
  #   expected_password = "apc"
  #   correct_credentials = 0
  #   connection_status = :not_connected

  #   correct_user_name = (expected_user_name == user_name)
  #   correct_password = (expected_password == password)
    
  #   case correct_user_name do
  #     true -> correct_credentials = correct_credentials + 1
  #     false -> :ok
  #   end

  #   case correct_password do
  #     true -> correct_credentials = correct_credentials + 1
  #     false -> :ok
  #   end

  #   case (correct_credentials == 2) do
  #     true -> 
  #       ## TODO
  #       ## perform login
  #       :connected
  #     false ->
  #       Logger.info "Incorrect username & password combination."
  #       :not_connected
  #   end

  # end

end
