defmodule DanteJournal.State do
  @moduledoc "The workspace state map and its pure transitions."
  alias DanteJournal.{Anchor, Classifier, Form, Notes, Preferences, Tercet, Text}

  @scopes [:canto, :cantica, :all]
  @groups [:canto, :type, :day]

  def initial(opts \\ []) do
    %{
      theme: Keyword.get(opts, :theme, :dark),
      english: Keyword.get(opts, :english, Text.default_english()),
      italian: Keyword.get(opts, :italian, false),
      preferences_path: Keyword.get(opts, :preferences_path),
      cantica: :inferno,
      canto: 1,
      # The tercet dictation falls back to when no anchor is spoken.
      tercet: nil,
      # Servers; nil when running without them (some tests).
      notes: Keyword.get(opts, :notes),
      recorder: Keyword.get(opts, :recorder),
      player: Keyword.get(opts, :player),
      recorder_status: :starting,
      # Key code watched for hold-to-talk (0 = off) and what the helper says about it.
      hotkey: Keyword.get(opts, :hotkey, 61),
      hotkey_status: :off,
      hotkey_down_at: nil,
      # nil, or the dictation in progress.
      recording: nil,
      # nil, or the note form in the card.
      form: nil,
      all_notes: [],
      note_counts: %{},
      notes_scope: Keyword.get(opts, :notes_scope, :canto),
      notes_group: Keyword.get(opts, :notes_group, :canto),
      notes_types: MapSet.new(),
      notes_query: "",
      notes_search_focus: 0,
      pending_delete: nil,
      playing: nil,
      palette: false,
      palette_query: "",
      palette_index: 0,
      palette_focus: 0,
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
    else
      state
    end
  end

  def go_to(state, %Anchor{} = anchor),
    do: select(state, anchor.cantica, anchor.canto, Anchor.tercet_number(anchor))

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

  def toggle_theme(state),
    do: %{state | theme: if(state.theme == :dark, do: :light, else: :dark)} |> remember()

  def toggle_italian(state), do: %{state | italian: not state.italian} |> remember()

  def set_english(state, english) do
    if english in Text.english_translations(),
      do: %{state | english: english} |> remember(),
      else: state
  end

  def set_hotkey(state, key) when key in [0, 61, 54, 62, 63] do
    if state.recorder,
      do: DanteJournal.Recorder.set_hotkey(state.recorder, if(key == 0, do: nil, else: key))

    %{state | hotkey: key, hotkey_status: if(key == 0, do: :off, else: state.hotkey_status)}
    |> remember()
  end

  def hotkey_name(61), do: "right ⌥"
  def hotkey_name(54), do: "right ⌘"
  def hotkey_name(62), do: "right ⌃"
  def hotkey_name(63), do: "fn"
  def hotkey_name(_), do: "off"

  defp remember(state) do
    Preferences.remember(state.preferences_path, state)
    state
  end

  # -- Notes: loading and the pane -------------------------------------------

  def refresh_notes(%{notes: nil} = state), do: state

  def refresh_notes(state) do
    %{state | all_notes: Notes.all(state.notes), note_counts: Notes.counts(state.notes)}
  end

  @doc "Notes anchored in the open canto."
  def canto_notes(state),
    do:
      Enum.filter(
        state.all_notes,
        &(&1.anchor.cantica == state.cantica and &1.anchor.canto == state.canto)
      )

  @doc "Notes of the open canto grouped by the tercet their anchor starts in."
  def notes_by_tercet(state),
    do: Enum.group_by(canto_notes(state), &Anchor.tercet_number(&1.anchor))

  def scopes, do: @scopes
  def groups, do: @groups

  def scope_label(:canto), do: "This canto"
  def scope_label(:cantica), do: "This cantica"
  def scope_label(:all), do: "Everything"

  def group_label(:canto), do: "By canto"
  def group_label(:type), do: "By type"
  def group_label(:day), do: "By day"

  def set_scope(state, scope) when scope in @scopes,
    do: %{state | notes_scope: scope} |> remember()

  def set_group(state, group) when group in @groups,
    do: %{state | notes_group: group} |> remember()

  def toggle_type_filter(state, type) do
    types =
      if MapSet.member?(state.notes_types, type),
        do: MapSet.delete(state.notes_types, type),
        else: MapSet.put(state.notes_types, type)

    %{state | notes_types: types}
  end

  def clear_filters(state), do: %{state | notes_types: MapSet.new(), notes_query: ""}

  def set_query(state, query), do: %{state | notes_query: query}

  @doc "The notes the pane shows: scope, then type filter, then search."
  def visible_notes(state) do
    query = String.downcase(String.trim(state.notes_query))

    state.all_notes
    |> Enum.filter(&in_scope?(&1, state))
    |> Enum.filter(
      &(MapSet.size(state.notes_types) == 0 or MapSet.member?(state.notes_types, &1.type))
    )
    |> Enum.filter(&(query == "" or matches?(&1, query)))
  end

  defp in_scope?(_note, %{notes_scope: :all}), do: true
  defp in_scope?(note, %{notes_scope: :cantica, cantica: c}), do: note.anchor.cantica == c

  defp in_scope?(note, %{cantica: c, canto: n}),
    do: note.anchor.cantica == c and note.anchor.canto == n

  defp matches?(note, query) do
    haystack =
      [
        note.text,
        Anchor.label(note.anchor),
        Classifier.label(note.type),
        Tercet.name(note.anchor.cantica)
      ]
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(haystack, query)
  end

  @doc "Visible notes in groups: `{key, heading, notes}`, in reading order."
  def grouped_notes(state) do
    notes = visible_notes(state)

    case state.notes_group do
      :canto ->
        notes
        |> Enum.group_by(&{&1.anchor.cantica, &1.anchor.canto})
        |> Enum.sort_by(fn {{c, n}, _} -> {cantica_index(c), n} end)
        |> Enum.map(fn {{c, n}, group} ->
          {"#{c}-#{n}", "#{Tercet.name(c)} · Canto #{Tercet.roman(n)}", by_line(group)}
        end)

      :type ->
        Classifier.types()
        |> Enum.map(fn type ->
          {Atom.to_string(type), Classifier.label(type),
           by_place(Enum.filter(notes, &(&1.type == type)))}
        end)
        |> Enum.reject(fn {_, _, group} -> group == [] end)

      :day ->
        notes
        |> Enum.group_by(&DateTime.to_date(&1.recorded_at))
        |> Enum.sort_by(fn {day, _} -> day end, {:desc, Date})
        |> Enum.map(fn {day, group} ->
          {Date.to_iso8601(day), Calendar.strftime(day, "%A, %B %-d"), by_place(group)}
        end)
    end
  end

  defp cantica_index(cantica), do: Enum.find_index(Tercet.cantiche(), &(&1 == cantica))
  defp by_line(notes), do: Enum.sort_by(notes, &{&1.anchor.from_line || 0, &1.id})

  defp by_place(notes),
    do:
      Enum.sort_by(
        notes,
        &{cantica_index(&1.anchor.cantica), &1.anchor.canto, &1.anchor.from_line || 0, &1.id}
      )

  # -- Dictation and the note form -------------------------------------------

  def begin_recording(state, id, clip),
    do: %{state | recording: %{id: id, clip: clip, text: "", ms: 0, phase: :arming}, notice: nil}

  @doc "Turns a finished transcript into a form for the card."
  def form_from_transcript(state, text, extra) do
    text = String.trim(text)

    if text == "" do
      if clip = Map.get(extra, :clip), do: File.rm(clip)
      %{state | recording: nil, notice: "Nothing was heard."}
    else
      {anchor, phrase, how} = Anchor.parse(text, state)

      %{
        state
        | recording: nil,
          form: Form.from_dictation(text, anchor, phrase, how, extra),
          notice: nil
      }
    end
  end

  @doc "Opens an empty form anchored to the selected tercet or the open canto."
  def new_typed_note(state) do
    {anchor, how} =
      case selection_anchor(state) do
        nil -> {canto_anchor(state), :position}
        anchor -> {anchor, :selection}
      end

    %{state | form: Form.typed(anchor, how), notice: nil}
  end

  def edit_note(state, id) do
    case Enum.find(state.all_notes, &(&1.id == id)) do
      nil -> state
      note -> %{state | form: Form.edit(note), pending_delete: nil} |> go_to(note.anchor)
    end
  end

  def update_form(%{form: nil} = state, _fun), do: state
  def update_form(state, fun), do: %{state | form: fun.(state.form)}

  @doc "The anchor for the reader's selected tercet, or nil when none is selected."
  def selection_anchor(%{tercet: nil}), do: nil

  def selection_anchor(state),
    do: Anchor.tercet(state.cantica, state.canto, state.tercet, line_count(state))

  def canto_anchor(state), do: %Anchor{cantica: state.cantica, canto: state.canto}

  def save_form(%{form: nil} = state), do: state

  def save_form(%{notes: nil} = state),
    do: %{state | form: nil, notice: "No notes folder; nothing saved."}

  def save_form(%{form: form} = state) do
    note = Form.to_note(form)

    cond do
      note.text == "" ->
        %{state | notice: "The note is empty."}

      true ->
        case Notes.save(state.notes, note) do
          :ok ->
            %{state | form: nil, notice: nil}
            |> refresh_notes()
            |> go_to(note.anchor)

          {:error, reason} ->
            %{state | notice: "Couldn't save the note: #{inspect(reason)}"}
        end
    end
  end

  def discard_form(%{form: nil} = state), do: state

  def discard_form(%{form: form} = state) do
    if form.existing == nil and form.clip, do: File.rm(form.clip)
    %{state | form: nil}
  end

  def request_delete(state, id), do: %{state | pending_delete: id}

  def delete_note(%{notes: nil} = state, _id), do: state

  def delete_note(state, id) do
    :ok = Notes.delete(state.notes, id)
    form = if state.form && state.form.id == id, do: nil, else: state.form

    %{
      state
      | pending_delete: nil,
        form: form,
        playing: if(state.playing == id, do: nil, else: state.playing)
    }
    |> refresh_notes()
  end

  # -- Export ------------------------------------------------------------------

  def export_title(state) do
    case state.notes_scope do
      :canto -> "#{Tercet.name(state.cantica)} · Canto #{Tercet.roman(state.canto)}"
      :cantica -> Tercet.name(state.cantica)
      :all -> "Dante Journal"
    end
  end

  def export_slug(state) do
    case state.notes_scope do
      :canto -> "#{state.cantica}-#{state.canto}"
      :cantica -> Atom.to_string(state.cantica)
      :all -> "dante-journal"
    end
  end

  # -- Command palette ---------------------------------------------------------

  def open_palette(state),
    do: %{
      state
      | palette: true,
        palette_query: "",
        palette_index: 0,
        palette_focus: state.palette_focus + 1
    }

  def close_palette(state), do: %{state | palette: false, palette_query: ""}

  @commands [
    {"toggle-recording", "Record a note", "⌘⇧D"},
    {"new-note", "Type a note", "⌘N"},
    {"toggle-italian", "Toggle the Italian column", "⌘I"},
    {"next-canto", "Next canto", "⌘⇧N"},
    {"previous-canto", "Previous canto", "⌘⇧P"},
    {"focus-search", "Search notes", "⌘F"},
    {"scope:canto", "Show notes from this canto", ""},
    {"scope:cantica", "Show notes from this cantica", ""},
    {"scope:all", "Show every note", ""},
    {"group:canto", "Group notes by canto", ""},
    {"group:type", "Group notes by type", ""},
    {"group:day", "Group notes by day", ""},
    {"export:md", "Export shown notes as Markdown", ""},
    {"export:txt", "Export shown notes as text", ""},
    {"toggle-theme", "Toggle dark and light", "⌘⇧L"},
    {"hotkey:61", "Hold-to-talk key: right Option", ""},
    {"hotkey:54", "Hold-to-talk key: right Command", ""},
    {"hotkey:62", "Hold-to-talk key: right Control", ""},
    {"hotkey:63", "Hold-to-talk key: fn", ""},
    {"hotkey:0", "Hold-to-talk: off", ""}
  ]

  @doc "Palette choices for the query: a place in the poem first, then commands."
  def choices(state) do
    query = String.trim(state.palette_query)
    down = String.downcase(query)

    place =
      case query != "" and Anchor.parse(query, %{state | tercet: nil}) do
        {%Anchor{} = anchor, _, :spoken} ->
          [
            %{
              event: "goto:" <> encode(anchor),
              label: "Go to " <> place_label(anchor),
              detail: "↵"
            }
          ]

        _ ->
          []
      end

    translations =
      for english <- Text.english_translations(),
          english != state.english,
          do: {"english:#{english}", "Read the #{Text.translation_name(english)} translation", ""}

    commands =
      for {event, label, detail} <- @commands ++ translations,
          down == "" or String.contains?(String.downcase(label), down),
          do: %{event: event, label: label, detail: detail}

    place ++ commands
  end

  defp place_label(%Anchor{from_line: nil} = a),
    do: "#{Tercet.name(a.cantica)} · Canto #{Tercet.roman(a.canto)}"

  defp place_label(%Anchor{} = a),
    do: "#{Tercet.name(a.cantica)} · Canto #{Tercet.roman(a.canto)}, line #{a.from_line}"

  def encode(%Anchor{} = a), do: "#{a.cantica}:#{a.canto}:#{a.from_line || 0}"

  def decode(string) do
    [cantica, canto, from] = String.split(string, ":")
    from = String.to_integer(from)

    %Anchor{
      cantica: String.to_existing_atom(cantica),
      canto: String.to_integer(canto),
      from_line: if(from > 0, do: from),
      to_line: if(from > 0, do: from)
    }
  end

  defp put_status(state) do
    %{state | status: "#{Tercet.name(state.cantica)} · Canto #{Tercet.roman(state.canto)}"}
  end
end
