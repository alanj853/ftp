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
    initial_state = %{ connection_status: status, current_directory: "/home", response: "" }
    GenServer.start_link(__MODULE__, initial_state, name: @server_name)
  end

  def init(state=%{connection_status: status, current_directory: cd, response: response}) do
    Logger.info "Session Started."
    {:ok, state}
  end

  def get_state() do
    GenServer.call __MODULE__, :get_state
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

  def make_directory(path) do
    GenServer.call __MODULE__, {:make_directory, path}
  end
  
  def remove_directory(path) do
    GenServer.call __MODULE__, {:remove_directory, path}
  end

  def remove_file(path) do
    GenServer.call __MODULE__, {:remove_file, path}
  end

  def system_type() do
    GenServer.call __MODULE__, :system_type
  end

  def feat() do
    GenServer.call __MODULE__, :feat
  end

  def type() do
    GenServer.call __MODULE__, :type
  end

  def pasv() do
    GenServer.call __MODULE__, :pasv
  end

  def port() do
    GenServer.call __MODULE__, :port
  end

  def handle_call(:get_state, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    {:reply, state, state}
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
            Logger.info "226 Files Found: #{files_as_string}\r\n"
            "226 #{files_as_string}\r\n"
          {:error, reason} ->
            Logger.info "550 ls command failed. Reason: #{inspect reason}\r\n"
            to_string(reason)
            "550 ls command failed. Reason: #{inspect reason}\r\n"
        end
      false ->
        Logger.info "You don't have permission to view this file/folder."
        "550 You don't have permission to view this file/folder.\r\n"
      end


    new_state=%{connection_status: status, current_directory: cd, response: new_response}
    {:reply, state, new_state}
  end

  
  def handle_call(:current_directory, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    Logger.debug "257 cd: #{inspect cd}"
    new_response = "257 \"#{cd}\"\r\n"
    new_state=%{connection_status: status, current_directory: cd, response: new_response}
    {:reply, state, new_state}
  end

  def handle_call({:change_directory, path}, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    {response, new_path} = case File.dir?(path) do
      true ->
        Logger.debug "250 Current Directory: #{path}"
        {"250 Current Directory: #{path}\r\n", path}
      false ->
        Logger.debug "550 Current path '#{path}' does not exist."
        {"550 Current path '#{path}' does not exist\r\n", cd}
    end
    new_state = %{connection_status: status, current_directory: new_path, response: response}
    {:reply, state, new_state}
  end

  def handle_call({:make_directory, path}, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    case File.mkdir_p(path) do
      :ok ->
        Logger.info "257 Directory #{path} created."
        response = "257 Directory #{path} created\r\n"
      {:error, reason} ->
        Logger.info "550 Directory #{path} could not be created. Reason: #{inspect reason}"
        response = "550 Directory #{path} could not be created. Reason: #{inspect reason}\r\n"
    end
    new_state=%{connection_status: status, current_directory: cd, response: response}
    {:reply, state, new_state}
  end

  def handle_call({:remove_directory, path}, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    case File.rmdir(path) do
      :ok ->
        Logger.info "200 Directory '#{path}' removed."
        response = "200 Directory '#{path}' removed\r\n"
      {:error, reason} ->
        Logger.info "550 Error removing directory '#{path}'. Reason: #{inspect reason}"
        response = "550 Error removing directory '#{path}'. Reason: #{inspect reason}\r\n"
    end
    new_state=%{connection_status: status, current_directory: cd, response: response}
    {:reply, state, new_state}
  end

  def handle_call({:remove_file, path}, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    case File.rm(path) do
      :ok->
        Logger.info "200 File '#{path}' removed."
        response = "200 File '#{path}' removed\r\n"
      {:error, reason} ->
        Logger.info "550 Error removing file '#{path}'. Reason: #{inspect reason}"
        response = "550 Error removing file '#{path}'. Reason: #{inspect reason}\r\n"
    end
    new_state=%{connection_status: status, current_directory: cd, response: response}
    {:reply, state, new_state}
  end

  def handle_call(:system_type, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    Logger.debug "215 UNIX Type: L8\r\n"
    new_response = "215 UNIX Type: L8\r\n"
    new_state=%{connection_status: status, current_directory: cd, response: new_response}
    {:reply, state, new_state}
  end

  def handle_call(:feat, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    Logger.debug "211 no-features\r\n"
    new_response = "211 no-features\r\n"
    new_state=%{connection_status: status, current_directory: cd, response: new_response}
    {:reply, state, new_state}
  end

  def handle_call(:type, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    Logger.debug "200 ASCII Non-print"
    new_response = "200 ASCII Non-print\r\n"
    new_state=%{connection_status: status, current_directory: cd, response: new_response}
    {:reply, state, new_state}
  end

  def handle_call(:pasv, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    Logger.debug "227 Entering Passive Mode"
    new_response = "227 Entering Passive Mode\r\n"
    new_state=%{connection_status: status, current_directory: cd, response: new_response}
    {:reply, state, new_state}
  end

  def handle_call(:port, _from, state=%{connection_status: status, current_directory: cd, response: response}) do
    Logger.debug "200 Okay"
    new_response = "200 Okay\r\n"
    new_state=%{connection_status: status, current_directory: cd, response: new_response}
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
