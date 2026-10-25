defmodule DanteJournal.Form do
  @moduledoc """
  The note form shown in the card: a new dictation, a typed note, or an
  existing note being edited. Text lives in a native `GPUI.Text.Buffer` when
  the native backend is present and in `text` otherwise (tests, and the
  single-line fallback input).
  """
  alias DanteJournal.{Anchor, Classifier}
  alias DanteJournal.Notes.Note

  defstruct id: nil,
            text: "",
            buffer: nil,
            # Keys the text surface so a replaced buffer mounts fresh.
            surface: 0,
            focus: 0,
            type: :note,
            anchor: nil,
            spoken_anchor: nil,
            phrase: "",
            how: :position,
            anchor_input: "",
            anchor_error: nil,
            clip: nil,
            ms: 0,
            source: :dictation,
            existing: nil,
            title: nil,
            tags: [],
            # What the model is still working on for this form.
            pending: MapSet.new(),
            # Once the reader sets these by hand, the model's suggestion is ignored.
            type_touched: false,
            anchor_touched: false

  @doc "A form for a finished dictation."
  def from_dictation(text, anchor, phrase, how, extra) do
    %__MODULE__{
      id: Map.get(extra, :id) || Note.new_id(),
      type: Classifier.classify(Anchor.strip_phrase(text, phrase)),
      anchor: anchor,
      spoken_anchor: if(how == :spoken, do: anchor),
      phrase: phrase,
      how: how,
      clip: Map.get(extra, :clip),
      ms: Map.get(extra, :ms, 0),
      source: :dictation
    }
    |> put_text(text)
  end

  @doc "An empty form for a typed note."
  def typed(anchor, how) do
    %__MODULE__{id: Note.new_id(), anchor: anchor, how: how, source: :typed}
    |> put_text("")
    |> focus()
  end

  @doc "A form holding an existing note."
  def edit(%Note{} = note) do
    %__MODULE__{
      id: note.id,
      type: note.type,
      anchor: note.anchor,
      phrase: note.anchor_phrase,
      how: :chosen,
      clip: nil,
      source: note.source,
      existing: note,
      title: note.title,
      tags: note.tags,
      type_touched: true,
      anchor_touched: true
    }
    |> put_text(note.text)
    |> focus()
  end

  def editing?(%__MODULE__{existing: nil}), do: false
  def editing?(%__MODULE__{}), do: true

  def title(%__MODULE__{existing: nil, source: :typed}), do: "NEW NOTE"
  def title(%__MODULE__{existing: nil}), do: "NEW NOTE"
  def title(%__MODULE__{}), do: "EDIT NOTE"

  @doc "Replaces the text, giving the surface a fresh buffer."
  def put_text(form, text) do
    case GPUI.Text.Buffer.new(text) do
      {:ok, buffer} ->
        %{form | text: text, buffer: buffer, surface: form.surface + 1}

      {:error, :native_backend_unavailable} ->
        %{form | text: text, buffer: nil, surface: form.surface + 1}
    end
  end

  @doc "Pulls the latest text out of the native buffer, if there is one."
  def sync(%__MODULE__{buffer: nil} = form), do: form

  def sync(%__MODULE__{buffer: buffer} = form) do
    {:ok, snapshot} = GPUI.Text.Buffer.snapshot(buffer)
    %{form | text: snapshot.text}
  end

  @doc "Text typed into the single-line fallback input."
  def change_text(form, text), do: %{form | text: text}

  def focus(form), do: %{form | focus: form.focus + 1}

  def set_type(form, type), do: %{form | type: type, type_touched: true}

  def set_anchor(form, %Anchor{} = anchor, how),
    do: %{form | anchor: anchor, how: how, anchor_error: nil, anchor_touched: true}

  @doc "Marks model work as outstanding or done."
  def expect(form, job), do: %{form | pending: MapSet.put(form.pending, job)}
  def settle(form, job), do: %{form | pending: MapSet.delete(form.pending, job)}

  @doc "Applies the model's classification unless the reader already chose a type."
  def suggest_type(%__MODULE__{} = form, %{type: type, title: title, tags: tags}) do
    form = settle(form, :classify)

    form = %{
      form
      | title: if(title == "", do: form.title, else: title),
        tags: if(tags == [], do: form.tags, else: tags)
    }

    if form.type_touched, do: form, else: %{form | type: type}
  end

  @doc "Applies the model's reading of the place unless the reader moved the anchor or lines are already known."
  def suggest_anchor(%__MODULE__{} = form, anchor) do
    form = settle(form, :locate)

    case anchor do
      %Anchor{from_line: from} when is_integer(from) ->
        if form.anchor_touched or form.anchor.from_line != nil,
          do: form,
          else: %{form | anchor: anchor, how: :model}

      _ ->
        form
    end
  end

  @doc "Applies a typed anchor such as “canto 9 stanza 24” or “Purg. 9.70–72”."
  def apply_anchor_input(form, "", _current), do: %{form | anchor_error: nil}

  def apply_anchor_input(form, input, current) do
    case Anchor.parse(input, %{current | tercet: nil}) do
      {anchor, _phrase, :spoken} ->
        %{form | anchor: anchor, how: :chosen, anchor_input: "", anchor_error: nil}

      _ ->
        %{form | anchor_error: "Couldn't read that as a place in the poem."}
    end
  end

  @doc "The note this form describes, ready to save."
  def to_note(%__MODULE__{} = form, now \\ DateTime.utc_now()) do
    form = sync(form)
    now = DateTime.truncate(now, :second)

    audio =
      cond do
        form.existing && form.existing.audio -> form.existing.audio
        form.clip && File.exists?(form.clip) -> Path.join("audio", Path.basename(form.clip))
        true -> nil
      end

    %Note{
      id: form.id,
      anchor: form.anchor,
      type: form.type,
      text: String.trim(form.text),
      anchor_phrase: form.phrase,
      title: form.title,
      tags: form.tags,
      audio: audio,
      source: form.source,
      recorded_at: if(form.existing, do: form.existing.recorded_at, else: now),
      edited_at: if(form.existing, do: now)
    }
  end
end
