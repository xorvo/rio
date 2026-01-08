defmodule WorkTree.AutoArchiver do
  @moduledoc """
  GenServer that automatically archives completed todos after 7 days.
  Runs every minute to check for eligible todos.
  """

  use GenServer

  alias WorkTree.MindMaps

  # Check every minute (60_000 ms)
  @check_interval 60_000

  # Archive todos completed more than 7 days ago
  @archive_after_days 7

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule the first check
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_and_archive, state) do
    archive_old_completed_todos()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_and_archive, @check_interval)
  end

  defp archive_old_completed_todos do
    todos = MindMaps.get_auto_archivable_todos(@archive_after_days)

    if length(todos) > 0 do
      MindMaps.archive_nodes(todos)
    end
  end
end
