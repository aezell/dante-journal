defmodule DanteJournal.PreferencesTest do
  use ExUnit.Case, async: true
  alias DanteJournal.Preferences

  test "preferences round-trip and ignore junk" do
    path =
      Path.join(
        System.tmp_dir!(),
        "dante-prefs-#{System.unique_integer([:positive])}/preferences.json"
      )

    on_exit(fn -> File.rm_rf(Path.dirname(path)) end)

    assert Preferences.restore([theme: :light], path) == [preferences_path: path, theme: :light]

    :ok =
      Preferences.remember(path, %{
        theme: :light,
        italian: true,
        english: :longfellow,
        notes_scope: :all,
        notes_group: :day
      })

    assert Preferences.load(path) |> Enum.sort() == [
             english: :longfellow,
             italian: true,
             notes_group: :day,
             notes_scope: :all,
             theme: :light
           ]

    # Explicit options win over remembered ones.
    assert Preferences.restore([theme: :dark], path)[:theme] == :dark
    assert Preferences.restore([], path)[:italian] == true

    File.write!(path, ~s({"theme":"neon","italian":"yes","notes_scope":"all","hotkey":-5}))
    assert Preferences.load(path) == [notes_scope: :all]
  end
end
