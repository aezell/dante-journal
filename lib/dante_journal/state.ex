defmodule DanteJournal.State do
  @moduledoc "The workspace state map and its pure transitions."
  alias DanteJournal.{Anchor, Classifier, Notes, Tercet, Text}
  alias DanteJournal.Notes.Note

  def initial(opts \\ []) do
    %{
      theme: Keyword.get(opts, :theme, :dark),
      english: Keyword.get(opts, :english, Text.default_english()),
      italian: false,
      cantica: :inferno,
      canto: 1,
      # The tercet dictation falls back to when no anchor is spoken.
      tercet: nil,
      # Servers; nil when running without them (some tests).
      notes: Keyword.get(opts, :notes),
      recorder: Keyword.get(opts, :recorder),
      recorder_status: :starting,
      # nil, or the dictation in progress.
      recording: nil,
      # nil, or a transcript awaiting confirmation.
      draft: nil,
      canto_notes: [],
      note_counts: %{},
      pending_delete: nil,
      notice: nil,
      status: "Inferno · Canto I"
    }
    |> refresh_notes()
  end

  # -- Navigation --------------------------------------------------------------

  def select(state, cantica, canto, tercet \\ nil) do
    if cantica in Text.cantiche() and canto in 1..Text.canto_count(cantica) do
      %{state | cantica: cantica, canto: canto, tercet: tercet, pending_delete: nil}
      |> put_status()
      |> refresh_notes()
    else
      state
    end
  end

  def next_canto(%{cantica: cantica, canto: canto} = state) do
    cond do
      canto < Text.canto_count(cantica) -> select(state, cantica, canto + 1)
      cantica == :inferno -> select(state, :purgatorio, 1)
      cantica == :purgatorio -> select(state, :paradiso, 1)
      true -> state
    end
  end

  def previous_canto(%{cantica: cantica, canto: canto} = state) do
    cond do
      canto > 1 -> select(state, cantica, canto - 1)
      cantica == :paradiso -> select(state, :purgatorio, 33)
      cantica == :purgatorio -> select(state, :inferno, 34)
      true -> state
    end
  end

  def select_tercet(state, n), do: %{state | tercet: if(state.tercet == n, do: nil, else: n)}

  def line_count(state), do: Text.line_count(state.english, state.cantica, state.canto)

  # -- Notes -------------------------------------------------------------------

  def refresh_notes(%{notes: nil} = state), do: state

  def refresh_notes(state) do
    %{
      state
      | canto_notes: Notes.for_canto(state.notes, state.cantica, state.canto),
        note_counts: Notes.counts(state.notes)
    }
  end

  @doc "Notes of the current canto grouped by the tercet their anchor starts in."
  def notes_by_tercet(state),
    do: Enum.group_by(state.canto_notes, &Anchor.tercet_number(&1.anchor))

  # -- Dictation ---------------------------------------------------------------

  def begin_recording(state, id, clip),
    do: %{state | recording: %{id: id, clip: clip, text: "", ms: 0, phase: :arming}, notice: nil}

  @doc "Turns a finished transcript into a draft for the confirm card."
  def draft_from(state, text, extra) do
    text = String.trim(text)

    if text == "" do
      %{state | recording: nil, draft: nil, notice: "Nothing was heard."}
    else
      {anchor, phrase, how} = Anchor.parse(text, state)

      draft =
        Map.merge(
          %{
            id: Map.get(extra, :id) || Note.new_id(),
            text: text,
            anchor: anchor,
            spoken_anchor: if(how == :spoken, do: anchor, else: nil),
            phrase: phrase,
            how: how,
            type: Classifier.classify(Anchor.strip_phrase(text, phrase)),
            clip: nil,
            ms: 0,
            source: :dictation
          },
          Map.take(extra, [:clip, :ms, :source])
        )

      %{state | recording: nil, draft: draft, notice: nil}
    end
  end

  def set_draft_type(%{draft: nil} = state, _type), do: state
  def set_draft_type(state, type), do: %{state | draft: %{state.draft | type: type}}

  def set_draft_anchor(%{draft: nil} = state, _anchor, _how), do: state

  def set_draft_anchor(state, anchor, how),
    do: %{state | draft: %{state.draft | anchor: anchor, how: how}}

  @doc "The anchor for the reader's selected tercet, or nil when none is selected."
  def selection_anchor(%{tercet: nil}), do: nil

  def selection_anchor(state),
    do: Anchor.tercet(state.cantica, state.canto, state.tercet, line_count(state))

  def canto_anchor(state), do: %Anchor{cantica: state.cantica, canto: state.canto}

  def save_draft(%{draft: nil} = state), do: state

  def save_draft(%{notes: nil} = state),
    do: %{state | draft: nil, notice: "No notes folder; nothing saved."}

  def save_draft(%{draft: draft} = state) do
    audio =
      if draft.clip && File.exists?(draft.clip), do: Path.join("audio", Path.basename(draft.clip))

    note = %Note{
      id: draft.id,
      anchor: draft.anchor,
      type: draft.type,
      text: draft.text,
      anchor_phrase: draft.phrase,
      audio: audio,
      source: draft.source,
      recorded_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    case Notes.save(state.notes, note) do
      :ok ->
        %{state | draft: nil, notice: nil}
        |> select(note.anchor.cantica, note.anchor.canto, Anchor.tercet_number(note.anchor))

      {:error, reason} ->
        %{state | notice: "Couldn't save the note: #{inspect(reason)}"}
    end
  end

  def discard_draft(%{draft: nil} = state), do: state

  def discard_draft(%{draft: draft} = state) do
    if draft.clip, do: File.rm(draft.clip)
    %{state | draft: nil}
  end

  def request_delete(state, id), do: %{state | pending_delete: id}

  def delete_note(%{notes: nil} = state, _id), do: state

  def delete_note(state, id) do
    :ok = Notes.delete(state.notes, id)
    %{state | pending_delete: nil} |> refresh_notes()
  end

  defp put_status(state) do
    %{state | status: "#{Tercet.name(state.cantica)} · Canto #{Tercet.roman(state.canto)}"}
  end
end
