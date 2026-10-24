defmodule DanteJournal.Notes do
  @moduledoc """
  The note store: one JSON file per note under the notes folder, read once
  into memory at start. Reads and writes go through this process so the
  folder and the in-memory copy never disagree.
  """
  use GenServer
  alias DanteJournal.Notes.Note

  # -- Client ------------------------------------------------------------------

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "The default notes folder, next to the imported texts."
  def default_dir,
    do: Path.join(:filename.basedir(:user_data, ~c"Dante Journal") |> to_string(), "notes")

  @doc "Where a new recording's clip should be written, before the note exists."
  def clip_path(server \\ __MODULE__, id), do: GenServer.call(server, {:clip_path, id})

  def save(server \\ __MODULE__, %Note{} = note), do: GenServer.call(server, {:save, note})
  def delete(server \\ __MODULE__, id), do: GenServer.call(server, {:delete, id})
  def get(server \\ __MODULE__, id), do: GenServer.call(server, {:get, id})
  def all(server \\ __MODULE__), do: GenServer.call(server, :all)

  @doc "Notes anchored in a canto, oldest first."
  def for_canto(server \\ __MODULE__, cantica, canto),
    do: GenServer.call(server, {:for_canto, cantica, canto})

  @doc "`{cantica, canto} => count` for the sidebar."
  def counts(server \\ __MODULE__), do: GenServer.call(server, :counts)

  # -- Server ------------------------------------------------------------------

  @impl true
  def init(opts) do
    dir = Keyword.get(opts, :dir, default_dir())
    File.mkdir_p!(dir)
    File.mkdir_p!(Path.join(dir, "audio"))
    {:ok, %{dir: dir, notes: load(dir)}}
  end

  @impl true
  def handle_call({:clip_path, id}, _from, state),
    do: {:reply, Path.join([state.dir, "audio", id <> ".wav"]), state}

  def handle_call({:save, note}, _from, state) do
    case write(state.dir, note) do
      :ok -> {:reply, :ok, %{state | notes: Map.put(state.notes, note.id, note)}}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:delete, id}, _from, state) do
    case Map.pop(state.notes, id) do
      {nil, _} ->
        {:reply, :ok, state}

      {note, notes} ->
        File.rm(path(state.dir, id))
        if note.audio, do: File.rm(Path.join(state.dir, note.audio))
        {:reply, :ok, %{state | notes: notes}}
    end
  end

  def handle_call({:get, id}, _from, state), do: {:reply, Map.get(state.notes, id), state}

  def handle_call(:all, _from, state), do: {:reply, sorted(Map.values(state.notes)), state}

  def handle_call({:for_canto, cantica, canto}, _from, state) do
    notes =
      state.notes
      |> Map.values()
      |> Enum.filter(&(&1.anchor.cantica == cantica and &1.anchor.canto == canto))
      |> sorted()

    {:reply, notes, state}
  end

  def handle_call(:counts, _from, state) do
    counts =
      state.notes |> Map.values() |> Enum.frequencies_by(&{&1.anchor.cantica, &1.anchor.canto})

    {:reply, counts, state}
  end

  # -- Files -------------------------------------------------------------------

  defp path(dir, id), do: Path.join(dir, id <> ".json")

  defp write(dir, note) do
    final = path(dir, note.id)
    temporary = final <> ".#{System.unique_integer([:positive])}.tmp"

    result =
      with :ok <- File.write(temporary, JSON.encode!(Note.to_map(note)), [:exclusive]),
           do: File.rename(temporary, final)

    if result != :ok, do: File.rm(temporary)
    result
  end

  defp load(dir) do
    dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.reduce(%{}, fn file, acc ->
      with {:ok, bytes} <- File.read(file),
           {:ok, map} <- JSON.decode(bytes),
           {:ok, note} <- Note.from_map(map) do
        Map.put(acc, note.id, note)
      else
        _ -> acc
      end
    end)
  end

  defp sorted(notes), do: Enum.sort_by(notes, & &1.id)
end
