defmodule DanteJournal.NotesTest do
  use ExUnit.Case, async: true
  alias DanteJournal.{Anchor, Notes}
  alias DanteJournal.Notes.Note

  setup do
    dir = Path.join(System.tmp_dir!(), "dante-notes-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  defp note(id, cantica, canto, from, text) do
    %Note{
      id: id,
      anchor: %Anchor{cantica: cantica, canto: canto, from_line: from, to_line: from && from + 2},
      type: :note,
      text: text,
      recorded_at: ~U[2026-10-24 16:00:00Z]
    }
  end

  test "notes round-trip through files and survive a restart", %{dir: dir} do
    {:ok, store} = Notes.start_link(dir: dir, name: nil)
    assert :ok = Notes.save(store, note("a", :inferno, 2, 34, "the leopard"))
    assert :ok = Notes.save(store, note("b", :inferno, 2, nil, "whole canto"))
    assert :ok = Notes.save(store, note("c", :paradiso, 33, 1, "Vergine madre"))

    assert Notes.counts(store) == %{{:inferno, 2} => 2, {:paradiso, 33} => 1}
    assert Enum.map(Notes.for_canto(store, :inferno, 2), & &1.id) == ["a", "b"]
    assert Notes.clip_path(store, "zz") == Path.join([dir, "audio", "zz.wav"])
    assert Path.wildcard(Path.join(dir, "*.json")) |> length() == 3

    GenServer.stop(store)
    {:ok, store} = Notes.start_link(dir: dir, name: nil)

    assert %Note{text: "the leopard", anchor: %Anchor{from_line: 34, to_line: 36}} =
             Notes.get(store, "a")

    assert :ok = Notes.delete(store, "a")
    assert Notes.get(store, "a") == nil
    refute File.exists?(Path.join(dir, "a.json"))
    assert length(Notes.all(store)) == 2
  end

  test "unreadable files are skipped", %{dir: dir} do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "junk.json"), "{not json")

    File.write!(
      Path.join(dir, "bad.json"),
      ~s({"id":"bad","anchor":{"cantica":"limbo","canto":1},"type":"note","text":"x","recorded_at":"2026-10-24T16:00:00Z"})
    )

    {:ok, store} = Notes.start_link(dir: dir, name: nil)
    assert Notes.all(store) == []
  end

  test "ids sort by time" do
    a = Note.new_id(~U[2026-10-24 16:00:00.123Z])
    b = Note.new_id(~U[2026-10-24 16:00:01.000Z])
    assert a < b
    assert a =~ ~r/^20261024T160000123-[0-9a-f]{6}$/
  end
end
