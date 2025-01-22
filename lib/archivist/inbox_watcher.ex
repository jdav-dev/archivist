defmodule Archivist.Worker do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    dir = Keyword.fetch!(opts, :dir)
    interval_seconds = Keyword.fetch!(opts, :interval_seconds)

    case FileSystem.start_link(
           backend: :fs_poll,
           dirs: [dir],
           interval: to_timeout(second: interval_seconds),
           name: :archivist_worker_file_monitor
         ) do
      {:ok, watcher_pid} ->
        FileSystem.subscribe(watcher_pid)
        {:ok, %{watcher_pid: watcher_pid}}

      {:error, {:already_started, watcher_pid}} ->
        FileSystem.subscribe(watcher_pid)
        {:ok, %{watcher_pid: watcher_pid}}

      :ignore ->
        {:error, :fs_ignore}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_info({:file_event, watcher_pid, {path, events}}, %{watcher_pid: watcher_pid} = state) do
    # Your own logic for path and events
    IO.inspect(events, label: path)

    {:noreply, state}
  end

  def handle_info({:file_event, watcher_pid, :stop}, %{watcher_pid: watcher_pid} = state) do
    {:stop, :fs_stop, state}
  end
end
