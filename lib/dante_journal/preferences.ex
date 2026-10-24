defmodule DanteJournal.Preferences do
  @moduledoc "A few remembered choices: theme, Italian column, translation, notes pane layout."

  @keys ~w(theme italian english notes_scope notes_group hotkey)a
  @allowed %{
    theme: [:dark, :light],
    italian: [true, false],
    english: [:mandelbaum, :longfellow],
    notes_scope: [:canto, :cantica, :all],
    notes_group: [:canto, :type, :day],
    # Key codes the helper can watch: right ⌥, right ⌘, right ⌃, fn; 0 is off.
    hotkey: [0, 61, 54, 62, 63]
  }

  def path,
    do:
      Path.join(
        :filename.basedir(:user_config, ~c"Dante Journal") |> to_string(),
        "preferences.json"
      )

  @doc "Merges remembered preferences under explicit options."
  def restore(opts, path \\ path()) do
    Enum.reduce(load(path), opts, fn {key, value}, acc -> Keyword.put_new(acc, key, value) end)
    |> Keyword.put(:preferences_path, path)
  end

  def remember(nil, _state), do: :ok

  def remember(path, state) do
    data = Map.new(@keys, fn key -> {Atom.to_string(key), Map.get(state, key)} end)
    temporary = path <> ".#{System.unique_integer([:positive])}.tmp"

    result =
      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- File.write(temporary, JSON.encode!(data), [:exclusive]),
           do: File.rename(temporary, path)

    if result != :ok, do: File.rm(temporary)
    result
  end

  def load(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, data} when is_map(data) <- JSON.decode(bytes) do
      for key <- @keys,
          value = decode(key, data[Atom.to_string(key)]),
          value != nil,
          into: [],
          do: {key, value}
    else
      _ -> []
    end
  end

  defp decode(key, value) when is_binary(value),
    do: Enum.find(@allowed[key], &(Atom.to_string(&1) == value))

  defp decode(key, value) when is_boolean(value) or is_integer(value),
    do: if(value in @allowed[key], do: value)

  defp decode(_key, _value), do: nil
end
