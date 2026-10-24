defmodule DanteJournal.View do
  @moduledoc "The root view: canto sidebar, the poem, and the notes pane."
  use GPUI.View
  alias GPUI.UI
  alias DanteJournal.{Anchor, Classifier, Notes, Recorder, State, Tercet, Text, Theme, UIKit}
  alias DanteJournal.Notes.Note

  @impl true
  def render(assigns) do
    ~GPUI"""
    <div class="flex flex-row w-full h-full text-[13px]" style={[background: {:theme, :canvas}, color: {:theme, :text}]}>
      {sidebar(assigns)}
      <div class="flex flex-col flex-1 min-w-0 h-full">
        {toolbar(assigns)}
        {reader(assigns)}
        {if assigns.recording, do: recording_banner(assigns), else: []}
        {if assigns.draft, do: draft_card(assigns), else: []}
        {status_bar(assigns)}
      </div>
      {notes_pane(assigns)}
    </div>
    """
    |> Theme.resolve(assigns.theme)
  end

  # `<.action>` in templates resolves to a local function.
  def action(assigns), do: UIKit.action(assigns)

  # -- Sidebar -----------------------------------------------------------------

  defp sidebar(assigns) do
    ~GPUI"""
    <div class="relative flex flex-col w-[220px] shrink-0 h-full" style={[background: {:theme, :sidebar}]}>
      {UIKit.vertical_rule()}
      <div window_control="drag" class="relative flex flex-row items-center h-[38px] shrink-0 px-4">
        {UIKit.rule()}
        <div class="w-[62px] shrink-0" />
        <text class="font-semibold" style={[color: {:theme, :accent}]}>Dante Journal</text>
      </div>
      <scroll id="canto-list" class="flex-1 min-h-0 w-full">
        <div class="flex flex-col w-full pb-4">
          {Enum.map(Text.cantiche(), &cantica_section(&1, assigns))}
        </div>
      </scroll>
    </div>
    """
  end

  defp cantica_section(cantica, state) do
    assigns = %{cantica: cantica, state: state, count: Text.canto_count(cantica)}

    ~GPUI"""
    <div class="flex flex-col w-full">
      <div class="flex flex-row items-center px-4 pt-4 pb-1 gap-2">
        {UIKit.heading(Tercet.name(assigns.cantica))}
        <text class="text-[10px]" style={[color: {:theme, :muted}]}>{assigns.count} cantos</text>
      </div>
      {Enum.map(1..assigns.count, &canto_row(assigns.cantica, &1, assigns.state))}
    </div>
    """
  end

  defp canto_row(cantica, canto, state) do
    assigns = %{
      id: "canto-#{cantica}-#{canto}",
      event: "select:#{cantica}:#{canto}",
      label: "Canto #{Tercet.roman(canto)}",
      selected: state.cantica == cantica and state.canto == canto,
      notes: Map.get(state.note_counts, {cantica, canto}, 0)
    }

    ~GPUI"""
    <.action id={assigns.id} phx-click={assigns.event} accessibility_label={assigns.label}
      class="flex flex-row items-center w-full h-[26px] px-4 gap-2 cursor-pointer"
      style={[background: if(assigns.selected, do: {:theme, :surface}, else: ~RGBA"00000000")]}>
      <text class="text-[12px]" style={[color: if(assigns.selected, do: {:theme, :accent}, else: {:theme, :text})]}>{assigns.label}</text>
      <div class="flex-1" />
      {note_badge(assigns.notes)}
    </.action>
    """
  end

  defp note_badge(0), do: []

  defp note_badge(count) do
    assigns = %{count: count}

    ~GPUI"""
    <text class="text-[10px]" style={[color: {:theme, :muted}]}>{assigns.count}</text>
    """
  end

  # -- Reader ------------------------------------------------------------------

  defp toolbar(assigns) do
    ~GPUI"""
    <div window_control="drag" class="relative flex flex-row items-center h-[38px] shrink-0 px-4 gap-2">
      {UIKit.rule()}
      <text class="font-semibold">{Tercet.name(assigns.cantica)}</text>
      <text style={[color: {:theme, :muted}]}>Canto {Tercet.roman(assigns.canto)}</text>
      <text class="text-[11px]" style={[color: {:theme, :muted}]}>· {Text.translation_name(assigns.english)}{if assigns.italian, do: " + Petrocchi", else: ""}</text>
      <div class="flex-1" />
      {record_button(assigns)}
      <UI.button id="previous-canto" label="‹" size="xs" variant="ghost" phx-click="previous-canto" />
      <UI.button id="next-canto" label="›" size="xs" variant="ghost" phx-click="next-canto" />
      <UI.button id="toggle-italian" label={if assigns.italian, do: "Hide Italian", else: "Italian"} size="xs" variant={if assigns.italian, do: "primary", else: "ghost"} phx-click="toggle-italian" />
    </div>
    """
  end

  defp record_button(%{recording: nil, recorder_status: :ready} = assigns) do
    ~GPUI"""
    <UI.button id="record" label="● Record  ⌘⇧D" size="xs" variant="ghost" phx-click="toggle-recording" disabled={not is_nil(assigns.draft)} />
    """
  end

  defp record_button(%{recording: nil} = _assigns) do
    ~GPUI"""
    <UI.button id="record" label="● Record" size="xs" variant="ghost" disabled={true} />
    """
  end

  defp record_button(_assigns) do
    ~GPUI"""
    <UI.button id="record" label="■ Stop  ⌘⇧D" size="xs" variant="danger" phx-click="toggle-recording" />
    """
  end

  defp reader(assigns) do
    tercets = Text.tercets(assigns.english, assigns.cantica, assigns.canto)

    italian =
      if assigns.italian,
        do:
          Text.tercets(:petrocchi, assigns.cantica, assigns.canto)
          |> Map.new(&{&1.number, &1.lines}),
        else: %{}

    assigns =
      Map.merge(assigns, %{
        tercets: tercets,
        italian_lines: italian,
        by_tercet: State.notes_by_tercet(assigns)
      })

    ~GPUI"""
    <UI.virtual_collection id={"reader-#{assigns.cantica}-#{assigns.canto}"} label={"#{Tercet.name(assigns.cantica)} canto #{assigns.canto}"}
      overdraw={400} class="flex-1 min-h-0 w-full px-6 py-6">
      {Enum.map(assigns.tercets, &tercet_item(&1, Map.get(assigns.italian_lines, &1.number), Map.get(assigns.by_tercet, &1.number, []), assigns))}
    </UI.virtual_collection>
    """
  end

  defp tercet_item(tercet, italian, notes, state) do
    assigns = %{
      tercet: tercet,
      italian: italian,
      notes: notes,
      selected: state.tercet == tercet.number,
      event: "tercet:#{tercet.number}"
    }

    UI.virtual_item(%{
      id: "tercet-#{tercet.number}",
      revision: if(italian, do: 1, else: 0) + 2 * length(notes),
      children: [tercet_row(assigns)]
    })
  end

  defp tercet_row(assigns) do
    ~GPUI"""
    <.action id={"pick-tercet-" <> Integer.to_string(assigns.tercet.number)} phx-click={assigns.event}
      accessibility_label={"Tercet " <> Integer.to_string(assigns.tercet.number)}
      class="flex flex-row w-full items-start gap-3 px-3 py-2 rounded-md cursor-pointer"
      style={[background: if(assigns.selected, do: {:theme, :surface}, else: ~RGBA"00000000")]}>
      <div class="flex flex-col w-10 shrink-0 items-end gap-1 pt-[3px]">
        <text class="text-[11px]" style={[color: if(assigns.selected, do: {:theme, :accent}, else: {:theme, :muted})]}>{if rem(assigns.tercet.number, 2) == 0 or assigns.selected or assigns.notes != [], do: Integer.to_string(assigns.tercet.from), else: ""}</text>
        {markers(assigns.notes)}
      </div>
      <div class="flex flex-col flex-1 min-w-0 gap-[2px]">
        {Enum.map(assigns.tercet.lines, &line(&1, :english))}
      </div>
      {italian_column(assigns.italian)}
    </.action>
    """
  end

  defp markers([]), do: []

  defp markers(notes) do
    assigns = %{notes: notes}

    ~GPUI"""
    <div class="flex flex-row flex-wrap justify-end gap-[3px] w-10">
      {Enum.map(assigns.notes, &marker/1)}
    </div>
    """
  end

  defp marker(note) do
    assigns = %{id: "marker-" <> note.id, color: Classifier.color(note.type)}

    ~GPUI"""
    <div id={assigns.id} class="w-[7px] h-[7px] rounded-full" style={[background: {:theme, assigns.color}]} />
    """
  end

  defp italian_column(nil), do: []

  defp italian_column(lines) do
    assigns = %{lines: lines}

    ~GPUI"""
    <div class="flex flex-col flex-1 min-w-0 gap-[2px]">
      {Enum.map(assigns.lines, &line(&1, :italian))}
    </div>
    """
  end

  defp line(text, language) do
    assigns = %{text: text, language: language}

    ~GPUI"""
    <text class="text-[15px] leading-[22px]" style={[color: if(assigns.language == :italian, do: {:theme, :muted}, else: {:theme, :text})]}>{assigns.text}</text>
    """
  end

  # -- Dictation ---------------------------------------------------------------

  defp recording_banner(assigns) do
    ~GPUI"""
    <div id="recording-banner" class="relative flex flex-row items-start shrink-0 px-5 py-3 gap-3" style={[background: {:theme, :surface}]}>
      {UIKit.rule_top()}
      <div class="w-[9px] h-[9px] rounded-full mt-[5px] shrink-0" style={[background: {:theme, :recording}]} />
      <div class="flex flex-col flex-1 min-w-0 gap-1">
        <div class="flex flex-row items-center gap-2">
          <text class="text-[11px] font-semibold" style={[color: {:theme, :recording}]}>{if assigns.recording.phase == :arming, do: "Listening…", else: "Recording"}</text>
          <text class="text-[11px]" style={[color: {:theme, :muted}]}>{clock(assigns.recording.ms)} · stops after a pause, or ⌘⇧D</text>
        </div>
        <text class="text-[14px] leading-[20px]">{if assigns.recording.text == "", do: "Say where you are, then your note: “Canto 2, stanza 12, …”", else: assigns.recording.text}</text>
      </div>
    </div>
    """
  end

  defp draft_card(assigns) do
    draft = assigns.draft
    selection = State.selection_anchor(assigns)

    assigns =
      Map.merge(assigns, %{
        d: draft,
        selection: selection,
        offer_selection: selection && selection != draft.anchor,
        offer_canto: draft.anchor.from_line != nil,
        offer_spoken: draft.spoken_anchor && draft.spoken_anchor != draft.anchor
      })

    ~GPUI"""
    <div id="draft-card" class="relative flex flex-col shrink-0 px-5 py-4 gap-3" style={[background: {:theme, :surface}]}>
      {UIKit.rule_top()}
      <div class="flex flex-row items-center gap-2">
        <text class="text-[11px] font-semibold" style={[color: {:theme, :muted}]}>NEW NOTE</text>
        <text id="draft-anchor" class="text-[12px] font-semibold" style={[color: {:theme, :accent}]}>{Anchor.label(assigns.d.anchor)}</text>
        <text class="text-[11px]" style={[color: {:theme, :muted}]}>{how_label(assigns.d.how)}</text>
        <div class="flex-1" />
        {if assigns.offer_spoken, do: small_button("draft-anchor-spoken", "Use spoken anchor"), else: []}
        {if assigns.offer_selection, do: small_button("draft-anchor-selection", "Use selected tercet"), else: []}
        {if assigns.offer_canto, do: small_button("draft-anchor-canto", "Whole canto"), else: []}
      </div>
      <div class="flex flex-row flex-wrap items-center gap-1">
        {Enum.map(Classifier.types(), &type_chip(&1, assigns.d.type))}
      </div>
      <text class="text-[14px] leading-[20px]">{assigns.d.text}</text>
      <div class="flex flex-row items-center gap-2">
        <text class="text-[11px]" style={[color: {:theme, :muted}]}>{if assigns.d.ms > 0, do: clock(assigns.d.ms) <> " of audio", else: ""}</text>
        <div class="flex-1" />
        <UI.button id="draft-discard" label="Discard" size="xs" variant="ghost" phx-click="draft-discard" />
        <UI.button id="draft-save" label="Save  ⌘S" size="xs" variant="primary" phx-click="draft-save" />
      </div>
    </div>
    """
  end

  defp how_label(:spoken), do: "from what you said"
  defp how_label(:selection), do: "the selected tercet"
  defp how_label(:position), do: "the open canto"
  defp how_label(:chosen), do: ""

  defp small_button(id, label) do
    assigns = %{id: id, label: label}

    ~GPUI"""
    <UI.button id={assigns.id} label={assigns.label} size="xs" variant="ghost" phx-click={assigns.id} />
    """
  end

  defp type_chip(type, current) do
    assigns = %{
      id: "draft-type-#{type}",
      event: "draft-type:#{type}",
      label: Classifier.label(type),
      active: type == current
    }

    ~GPUI"""
    <UI.button id={assigns.id} label={assigns.label} size="xs" variant={if assigns.active, do: "primary", else: "ghost"} phx-click={assigns.event} />
    """
  end

  defp clock(ms) do
    seconds = div(ms, 1000)
    "#{div(seconds, 60)}:#{String.pad_leading(Integer.to_string(rem(seconds, 60)), 2, "0")}"
  end

  # -- Notes pane --------------------------------------------------------------

  defp notes_pane(assigns) do
    ~GPUI"""
    <div class="relative flex flex-col w-[320px] shrink-0 h-full" style={[background: {:theme, :sidebar}]}>
      <div class="absolute top-0 bottom-0 left-0 w-[1px]" style={[background: {:theme, :border}]} />
      <div class="relative flex flex-row items-center h-[38px] shrink-0 px-4 gap-2">
        {UIKit.rule()}
        <text class="font-semibold">Notes</text>
        <text class="text-[11px]" style={[color: {:theme, :muted}]}>{Tercet.abbreviation(assigns.cantica)} {assigns.canto} · {length(assigns.canto_notes)}</text>
      </div>
      <scroll id="notes-list" class="flex-1 min-h-0 w-full">
        <div class="flex flex-col w-full px-3 py-3 gap-2">
          {if assigns.canto_notes == [], do: empty_notes(assigns), else: Enum.map(assigns.canto_notes, &note_card(&1, assigns))}
        </div>
      </scroll>
    </div>
    """
  end

  defp empty_notes(assigns) do
    ~GPUI"""
    <text class="text-[12px] leading-[18px] px-1 pt-2" style={[color: {:theme, :muted}]}>{if assigns.recorder_status == :ready, do: "No notes in this canto yet. Press ⌘⇧D and say where you are, then your note.", else: "No notes in this canto yet."}</text>
    """
  end

  defp note_card(%Note{} = note, state) do
    assigns = %{
      note: note,
      selected: state.tercet != nil and Anchor.tercet_number(note.anchor) == state.tercet,
      deleting: state.pending_delete == note.id,
      jump:
        if(Anchor.tercet_number(note.anchor),
          do: "tercet:#{Anchor.tercet_number(note.anchor)}",
          else: "noop"
        ),
      body: Anchor.strip_phrase(note.text, note.anchor_phrase),
      time: Calendar.strftime(note.recorded_at, "%b %-d, %H:%M")
    }

    ~GPUI"""
    <div id={"note-" <> assigns.note.id} class="relative flex flex-col w-full rounded-md px-3 py-2 gap-2"
      style={[background: if(assigns.selected, do: {:theme, :surface}, else: {:theme, :canvas})]}>
      <div class="flex flex-row items-center gap-2">
        <div class="w-[7px] h-[7px] rounded-full" style={[background: {:theme, Classifier.color(assigns.note.type)}]} />
        <text class="text-[11px] font-semibold" style={[color: {:theme, Classifier.color(assigns.note.type)}]}>{Classifier.label(assigns.note.type)}</text>
        <.action id={"jump-" <> assigns.note.id} phx-click={assigns.jump} accessibility_label="Show in the poem" class="cursor-pointer">
          <text class="text-[11px]" style={[color: {:theme, :accent}]}>{Anchor.label(assigns.note.anchor)}</text>
        </.action>
        <div class="flex-1" />
        <text class="text-[10px]" style={[color: {:theme, :muted}]}>{assigns.time}</text>
      </div>
      <text class="text-[13px] leading-[19px]">{assigns.body}</text>
      <div class="flex flex-row items-center gap-1">
        <div class="flex-1" />
        {if assigns.deleting do
          [small_button("note-delete-cancel", "Keep"), delete_button("note-delete-confirm:" <> assigns.note.id, "Delete for good", "danger")]
        else
          [delete_button("note-delete:" <> assigns.note.id, "Delete", "ghost")]
        end}
      </div>
    </div>
    """
  end

  defp delete_button(event, label, variant) do
    assigns = %{id: String.replace(event, ":", "-"), event: event, label: label, variant: variant}

    ~GPUI"""
    <UI.button id={assigns.id} label={assigns.label} size="xs" variant={assigns.variant} phx-click={assigns.event} />
    """
  end

  # -- Status ------------------------------------------------------------------

  defp status_bar(assigns) do
    ~GPUI"""
    <div class="relative flex flex-row items-center h-7 shrink-0 px-4 gap-3">
      {UIKit.rule_top()}
      <text id="status" class="text-[11px]" style={[color: {:theme, :muted}]}>{assigns.status}</text>
      {if assigns.notice, do: notice(assigns.notice), else: []}
      <div class="flex-1" />
      <text class="text-[11px]" style={[color: {:theme, :muted}]}>{recorder_label(assigns.recorder_status)}</text>
      <text class="text-[11px]" style={[color: {:theme, :muted}]}>{selection_label(assigns)}</text>
    </div>
    """
  end

  defp notice(text) do
    assigns = %{text: text}

    ~GPUI"""
    <text id="notice" class="text-[11px]" style={[color: {:theme, :recording}]}>{assigns.text}</text>
    """
  end

  defp recorder_label(:ready), do: "Mic ready"
  defp recorder_label(:starting), do: "Starting transcription…"
  defp recorder_label({:unavailable, _}), do: "Transcription unavailable"

  defp selection_label(%{tercet: nil}), do: "No tercet selected"

  defp selection_label(%{tercet: n, english: english, cantica: cantica, canto: canto}) do
    {from, to} = Tercet.range(n, Text.line_count(english, cantica, canto))
    Tercet.label(cantica, canto, from, to)
  end

  # -- Events ------------------------------------------------------------------

  @impl true
  def handle_event("select:" <> rest, _event, state) do
    [cantica, canto] = String.split(rest, ":")
    {:noreply, State.select(state, String.to_existing_atom(cantica), String.to_integer(canto))}
  end

  def handle_event("tercet:" <> n, _event, state),
    do: {:noreply, State.select_tercet(state, String.to_integer(n))}

  def handle_event("next-canto", _event, state), do: {:noreply, State.next_canto(state)}
  def handle_event("previous-canto", _event, state), do: {:noreply, State.previous_canto(state)}

  def handle_event("toggle-italian", _event, state),
    do: {:noreply, %{state | italian: not state.italian}}

  def handle_event("toggle-theme", _event, state),
    do: {:noreply, %{state | theme: if(state.theme == :dark, do: :light, else: :dark)}}

  def handle_event("toggle-recording", _event, %{recording: nil} = state) do
    cond do
      state.draft != nil ->
        {:noreply, %{state | notice: "Save or discard the note first."}}

      state.recorder == nil or state.recorder_status != :ready ->
        {:noreply, %{state | notice: "Transcription isn't ready."}}

      true ->
        id = Note.new_id()

        clip =
          if state.notes,
            do: Notes.clip_path(state.notes, id),
            else: Path.join(System.tmp_dir!(), id <> ".wav")

        Recorder.start_recording(state.recorder, clip)
        {:noreply, State.begin_recording(state, id, clip)}
    end
  end

  def handle_event("toggle-recording", _event, state) do
    Recorder.stop_recording(state.recorder)
    {:noreply, state}
  end

  def handle_event("draft-type:" <> type, _event, state),
    do: {:noreply, State.set_draft_type(state, String.to_existing_atom(type))}

  def handle_event("draft-anchor-selection", _event, state) do
    case State.selection_anchor(state) do
      nil -> {:noreply, state}
      anchor -> {:noreply, State.set_draft_anchor(state, anchor, :chosen)}
    end
  end

  def handle_event("draft-anchor-canto", _event, state),
    do: {:noreply, State.set_draft_anchor(state, State.canto_anchor(state), :chosen)}

  def handle_event(
        "draft-anchor-spoken",
        _event,
        %{draft: %{spoken_anchor: %Anchor{} = anchor}} = state
      ),
      do: {:noreply, State.set_draft_anchor(state, anchor, :spoken)}

  def handle_event("draft-save", _event, state), do: {:noreply, State.save_draft(state)}
  def handle_event("draft-discard", _event, state), do: {:noreply, State.discard_draft(state)}

  def handle_event("note-delete:" <> id, _event, state),
    do: {:noreply, State.request_delete(state, id)}

  def handle_event("note-delete-cancel", _event, state),
    do: {:noreply, %{state | pending_delete: nil}}

  def handle_event("note-delete-confirm:" <> id, _event, state),
    do: {:noreply, State.delete_note(state, id)}

  def handle_event(_other, _event, state), do: {:noreply, state}

  # -- Messages from workers ---------------------------------------------------

  @impl true
  def handle_info(:refresh_notes, state), do: {:noreply, State.refresh_notes(state)}

  def handle_info({:recorder, :ready}, state), do: {:noreply, %{state | recorder_status: :ready}}

  def handle_info({:recorder, {:unavailable, reason}}, state),
    do:
      {:noreply,
       %{state | recorder_status: {:unavailable, reason}, recording: nil, notice: reason}}

  def handle_info({:recorder, :started}, %{recording: %{} = recording} = state),
    do: {:noreply, %{state | recording: %{recording | phase: :recording}}}

  def handle_info({:recorder, {:partial, text}}, %{recording: %{} = recording} = state),
    do: {:noreply, %{state | recording: %{recording | text: text}}}

  def handle_info({:recorder, {:tick, ms}}, %{recording: %{} = recording} = state),
    do: {:noreply, %{state | recording: %{recording | ms: ms}}}

  def handle_info(
        {:recorder, {:stopped, %{text: text} = result}},
        %{recording: %{} = recording} = state
      ) do
    {:noreply,
     State.draft_from(state, text, %{
       id: recording.id,
       clip: result.clip || recording.clip,
       ms: result.ms || 0
     })}
  end

  def handle_info({:recorder, {:transcript, %{text: text}}}, state),
    do: {:noreply, State.draft_from(state, text, %{source: :dictation})}

  def handle_info({:recorder, {:error, message}}, state),
    do: {:noreply, %{state | recording: nil, notice: message}}

  def handle_info(_message, state), do: {:noreply, state}
end
