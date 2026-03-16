defmodule Rio.Inbox.InboxExpirer do
  @moduledoc """
  GenServer that automatically expires stale inbox items.
  Runs every minute to check for items past their expires_at.
  """

  use GenServer

  alias Rio.Inbox

  @check_interval 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_and_expire, state) do
    Inbox.expire_stale_items()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_and_expire, @check_interval)
  end
end
