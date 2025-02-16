defmodule Archivist.Worker do
  use GenServer

  alias NimbleCSV.RFC4180, as: CSV

  require Logger

  defstruct [:archive, :check_interval, :inbox, :log_file, failed: MapSet.new()]

  @archive_log_basename "archive.csv"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    case Archivist.init() do
      :ok ->
        state = %__MODULE__{
          archive: Keyword.fetch!(opts, :archive),
          check_interval: Keyword.fetch!(opts, :check_interval),
          inbox: Keyword.fetch!(opts, :inbox)
        }

        Logger.info("Watching inbox: #{inspect(state.inbox)}")

        {:ok, state, {:continue, :next_file}}

      :error ->
        {:stop, :archivist_init_failed}
    end
  end

  @impl GenServer
  def handle_continue(:next_file, state) do
    case next_file(state) do
      path when is_binary(path) -> {:noreply, state, {:continue, {:archive, path}}}
      nil -> {:noreply, state, state.check_interval}
    end
  end

  def handle_continue({:archive, path}, state) do
    Logger.info("Archiving #{inspect(path)}")

    with :ok <- Archivist.ocr_pdf(path),
         {:ok, extracted_info} <- Archivist.extract_pdf_information(path),
         :ok <- move_file(path, extracted_info, state) do
      {:noreply, state, {:continue, :next_file}}
    else
      error ->
        Logger.error("Failed to archive #{inspect(Path.basename(path))}: #{inspect(error)}")
        updated_state = struct!(state, failed: MapSet.put(state.failed, path))
        {:noreply, updated_state, {:continue, :next_file}}
    end
  end

  defp move_file(path, extracted_info, state) do
    archive_filename =
      "#{extracted_info.date}_#{extracted_info.source}_#{extracted_info.title}.pdf"

    File.mkdir_p!(state.archive)
    archive_path = Path.join(state.archive, archive_filename)

    Logger.info("Moving #{inspect(Path.basename(path))} to #{inspect(archive_path)}")

    with false <- File.exists?(archive_path),
         # Format and rm files in seperate steps in case inbox and archive are different devices.
         :ok <- File.cp(path, archive_path),
         :ok <- File.rm(path) do
      csv_entry =
        CSV.dump_to_iodata([
          [
            System.system_time(:second),
            Path.basename(path),
            archive_filename
          ]
        ])

      File.write!(Path.join(state.archive, @archive_log_basename), csv_entry, [:append, :sync])
      :ok
    else
      true ->
        # Leave the file in-place, let it run again.
        Logger.notice("Skipping #{inspect(archive_path)} (file exists)")
        :ok

      error ->
        error
    end
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    {:noreply, state, {:continue, :next_file}}
  end

  defp next_file(state) do
    state.inbox
    |> Path.join("*.pdf")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      {path, File.lstat!(path, time: :posix)}
    end)
    |> Enum.filter(fn {path, stat} ->
      stat.type == :regular and not MapSet.member?(state.failed, path)
    end)
    |> Enum.sort_by(fn {_path, stat} -> stat.ctime end)
    |> List.first({nil, nil})
    |> elem(0)
  end
end
