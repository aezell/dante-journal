defmodule DanteJournal.Notes.Note do
  @moduledoc "One journal note and its JSON file shape."
  alias DanteJournal.Anchor

  @enforce_keys [:id, :anchor, :type, :text, :recorded_at]
  defstruct [
    :id,
    :anchor,
    :type,
    :text,
    :recorded_at,
    :edited_at,
    anchor_phrase: "",
    audio: nil,
    source: :dictation,
    tags: []
  ]

  @types DanteJournal.Classifier.types()

  @doc "A sortable identifier: UTC timestamp then random suffix."
  def new_id(now \\ DateTime.utc_now()) do
    {micro, _} = now.microsecond

    stamp =
      Calendar.strftime(now, "%Y%m%dT%H%M%S") <> String.pad_leading("#{div(micro, 1000)}", 3, "0")

    suffix = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
    stamp <> "-" <> suffix
  end

  def to_map(%__MODULE__{} = note) do
    %{
      "id" => note.id,
      "anchor" => %{
        "cantica" => Atom.to_string(note.anchor.cantica),
        "canto" => note.anchor.canto,
        "from_line" => note.anchor.from_line,
        "to_line" => note.anchor.to_line
      },
      "type" => Atom.to_string(note.type),
      "text" => note.text,
      "anchor_phrase" => note.anchor_phrase,
      "audio" => note.audio,
      "source" => Atom.to_string(note.source),
      "tags" => note.tags,
      "recorded_at" => DateTime.to_iso8601(note.recorded_at),
      "edited_at" => note.edited_at && DateTime.to_iso8601(note.edited_at)
    }
  end

  def from_map(
        %{
          "id" => id,
          "anchor" => anchor,
          "type" => type,
          "text" => text,
          "recorded_at" => recorded
        } = map
      )
      when is_binary(id) and is_map(anchor) and is_binary(text) and is_binary(recorded) do
    with {:ok, cantica} <- cantica(anchor["cantica"]),
         canto when is_integer(canto) <- anchor["canto"],
         {:ok, recorded_at, _} <- DateTime.from_iso8601(recorded) do
      {:ok,
       %__MODULE__{
         id: id,
         anchor: %Anchor{
           cantica: cantica,
           canto: canto,
           from_line: anchor["from_line"],
           to_line: anchor["to_line"]
         },
         type: safe_atom(type, @types) || :note,
         text: text,
         anchor_phrase: map["anchor_phrase"] || "",
         audio: map["audio"],
         source: safe_atom(map["source"], [:dictation, :typed]) || :dictation,
         tags: Enum.filter(map["tags"] || [], &is_binary/1),
         recorded_at: recorded_at,
         edited_at: parse_optional(map["edited_at"])
       }}
    else
      _ -> :error
    end
  end

  def from_map(_), do: :error

  defp cantica(name) when name in ["inferno", "purgatorio", "paradiso"],
    do: {:ok, String.to_existing_atom(name)}

  defp cantica(_), do: :error

  defp safe_atom(value, allowed) when is_binary(value),
    do: Enum.find(allowed, &(Atom.to_string(&1) == value))

  defp safe_atom(_, _), do: nil

  defp parse_optional(nil), do: nil

  defp parse_optional(string) do
    case DateTime.from_iso8601(string) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
