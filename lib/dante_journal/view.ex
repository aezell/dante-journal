defmodule DanteJournal.View do
  @moduledoc "The root view: canto sidebar, the poem, the note card, and the notes pane."
  use GPUI.View
  alias GPUI.UI
  alias GPUI.UI.Overlay

  alias DanteJournal.{
    Anchor,
    Classifier,
    Export,
    Form,
    Notes,
    Player,
    Recorder,
    State,
    Tercet,
    Text,
    Theme,
    UIKit
  }

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
        {if assigns.form, do: form_card(assigns), else: []}
        {status_bar(assigns)}
      </div>
      {notes_pane(assigns)}
      {palette(assigns)}
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
      <div window_control="drag" class="relative flex flex-row items-center h-[38px] shrink-0 px-4 gap-2">
        {UIKit.rule()}
        <div class="w-[62px] shrink-0" />
        <text class="font-semibold" style={[color: {:theme, :accent}]}>Dante Journal</text>
        <div class="flex-1" />
        <UI.button id="open-palette" label="⌘K" size="xs" variant="ghost" phx-click="open-palette" />
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
      <UI.button id="new-note" label="+ Note" size="xs" variant="ghost" phx-click="new-note" disabled={not is_nil(assigns.form)} />
      <UI.button id="previous-canto" label="‹" size="xs" variant="ghost" phx-click="previous-canto" />
      <UI.button id="next-canto" label="›" size="xs" variant="ghost" phx-click="next-canto" />
      <UI.button id="toggle-italian" label={if assigns.italian, do: "Hide Italian", else: "Italian"} size="xs" variant={if assigns.italian, do: "primary", else: "ghost"} phx-click="toggle-italian" />
    </div>
    """
  end

  defp record_button(%{recording: nil, recorder_status: :ready} = assigns) do
    ~GPUI"""
    <UI.button id="record" label={"● Record  " <> record_hint(assigns)} size="xs" variant="ghost" phx-click="toggle-recording" disabled={not is_nil(assigns.form)} />
    """
  end

  defp record_button(%{recording: nil} = _assigns) do
    ~GPUI"""
    <UI.button id="record" label="● Record" size="xs" variant="ghost" disabled={true} />
    """
  end

  defp record_button(assigns) do
    ~GPUI"""
    <UI.button id="record" label={"■ Stop  " <> stop_hint(assigns)} size="xs" variant="danger" phx-click="toggle-recording" />
    """
  end

  # The key that starts a dictation: the hold-to-talk key when one is
  # listening, otherwise the window shortcut (which always works too).
  defp record_hint(%{hotkey_status: :listening, hotkey: key}),
    do: "hold " <> State.hotkey_name(key)

  defp record_hint(_assigns), do: "⌘⇧D"

  defp stop_hint(%{hotkey_status: :listening, hotkey: key}),
    do: "release " <> State.hotkey_name(key)

  defp stop_hint(_assigns), do: "⌘⇧D"

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
          <text class="text-[11px]" style={[color: {:theme, :muted}]}>{clock(assigns.recording.ms)} · stops after a pause, {stop_hint(assigns)}, or ⌘⇧D</text>
        </div>
        <text class="text-[14px] leading-[20px]">{if assigns.recording.text == "", do: "Say where you are, then your note: “Canto 2, stanza 12, …”", else: assigns.recording.text}</text>
      </div>
    </div>
    """
  end

  # -- The note card (new dictation, typed note, or edit) ----------------------

  defp form_card(assigns) do
    form = assigns.form
    selection = State.selection_anchor(assigns)

    assigns =
      Map.merge(assigns, %{
        f: form,
        offer_selection: selection && selection != form.anchor,
        offer_canto: form.anchor.from_line != nil,
        offer_spoken: form.spoken_anchor && form.spoken_anchor != form.anchor
      })

    ~GPUI"""
    <div id="form-card" class="relative flex flex-col shrink-0 px-5 py-4 gap-3" style={[background: {:theme, :surface}]}>
      {UIKit.rule_top()}
      <div class="flex flex-row items-center gap-2">
        <text class="text-[11px] font-semibold" style={[color: {:theme, :muted}]}>{Form.title(assigns.f)}</text>
        <text id="form-anchor" class="text-[12px] font-semibold" style={[color: {:theme, :accent}]}>{Anchor.label(assigns.f.anchor)}</text>
        <text class="text-[11px]" style={[color: {:theme, :muted}]}>{how_label(assigns.f.how)}</text>
        <div class="flex-1" />
        {if assigns.offer_spoken, do: small_button("form-anchor-spoken", "Use spoken anchor"), else: []}
        {if assigns.offer_selection, do: small_button("form-anchor-selection", "Use selected tercet"), else: []}
        {if assigns.offer_canto, do: small_button("form-anchor-canto", "Whole canto"), else: []}
        <UI.input id="form-anchor-input" label="Move to" placeholder="Move to… e.g. Purg. 9.70 or canto 9 stanza 24" size="sm"
          value={assigns.f.anchor_input} phx-change="form-anchor-input" phx-submit="form-anchor-apply" class="w-[260px]" />
      </div>
      {if assigns.f.anchor_error, do: notice(assigns.f.anchor_error, "form-anchor-error"), else: []}
      <div class="flex flex-row flex-wrap items-center gap-1">
        {Enum.map(Classifier.types(), &type_chip(&1, assigns.f.type))}
      </div>
      {form_text(assigns.f)}
      <div class="flex flex-row items-center gap-2">
        <text class="text-[11px]" style={[color: {:theme, :muted}]}>{if assigns.f.ms > 0, do: clock(assigns.f.ms) <> " of audio · ", else: ""}Enter adds a line · ⌘S saves</text>
        <div class="flex-1" />
        <UI.button id="form-discard" label={if Form.editing?(assigns.f), do: "Cancel", else: "Discard"} size="xs" variant="ghost" phx-click="form-discard" />
        <UI.button id="form-save" label="Save  ⌘S" size="xs" variant="primary" phx-click="form-save" />
      </div>
    </div>
    """
  end

  # The native text surface when a buffer exists; a single-line input otherwise.
  defp form_text(%Form{buffer: nil} = form) do
    assigns = %{f: form}

    ~GPUI"""
    <UI.input id="form-text-input" label="Note text" placeholder="Your note" value={assigns.f.text}
      focus_request={assigns.f.focus} phx-change="form-text" phx-submit="form-save" class="w-full" />
    """
  end

  defp form_text(form) do
    assigns = %{f: form}

    ~GPUI"""
    <text_surface id={"form-text-#{assigns.f.surface}"} buffer={assigns.f.buffer} focus_request={assigns.f.focus}
      soft_wrap={true} auto_grow={true} min_lines={2} max_lines={10} submit_policy="newline"
      phx-transaction="form-transaction" class="w-full rounded-md px-3 py-2 text-[14px]"
      style={[background: {:theme, :canvas}]} />
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
      id: "form-type-#{type}",
      event: "form-type:#{type}",
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
    groups = State.grouped_notes(assigns)
    shown = Enum.reduce(groups, 0, fn {_, _, notes}, n -> n + length(notes) end)

    assigns =
      Map.merge(assigns, %{
        groups: groups,
        shown: shown,
        filtered: MapSet.size(assigns.notes_types) > 0 or assigns.notes_query != ""
      })

    ~GPUI"""
    <div class="relative flex flex-col w-[340px] shrink-0 h-full" style={[background: {:theme, :sidebar}]}>
      <div class="absolute top-0 bottom-0 left-0 w-[1px]" style={[background: {:theme, :border}]} />
      <div class="relative flex flex-row items-center h-[38px] shrink-0 px-4 gap-2">
        {UIKit.rule()}
        <text class="font-semibold">Notes</text>
        <text id="notes-shown" class="text-[11px]" style={[color: {:theme, :muted}]}>{assigns.shown} of {length(assigns.all_notes)}</text>
        <div class="flex-1" />
        <UI.button id="export-copy" label="Copy MD" size="xs" variant="ghost" clipboard_text={Export.markdown(State.visible_notes(assigns), assigns.english, State.export_title(assigns))} phx-clipboard-write="export-copied" />
        <UI.button id="export-md" label="Save MD" size="xs" variant="ghost" phx-click="export:md" />
        <UI.button id="export-txt" label="Save TXT" size="xs" variant="ghost" phx-click="export:txt" />
      </div>
      <div class="flex flex-col px-3 pt-3 gap-2 shrink-0">
        <UI.input id="notes-search" label="Search notes" placeholder="Search notes…  ⌘F" size="sm" value={assigns.notes_query}
          focus_request={assigns.notes_search_focus} phx-change="notes-query" class="w-full" />
        <div class="flex flex-row items-center gap-1">
          {Enum.map(State.scopes(), &scope_chip(&1, assigns.notes_scope))}
          <div class="flex-1" />
          {Enum.map(State.groups(), &group_chip(&1, assigns.notes_group))}
        </div>
        <div class="flex flex-row flex-wrap items-center gap-1">
          {Enum.map(Classifier.types(), &type_filter_chip(&1, assigns.notes_types))}
          {if assigns.filtered, do: small_button("notes-clear-filters", "Clear"), else: []}
        </div>
      </div>
      <scroll id="notes-list" class="flex-1 min-h-0 w-full">
        <div class="flex flex-col w-full px-3 py-3 gap-2">
          {if assigns.groups == [], do: empty_notes(assigns), else: Enum.map(assigns.groups, &note_group(&1, assigns))}
        </div>
      </scroll>
    </div>
    """
  end

  defp scope_chip(scope, current) do
    assigns = %{
      id: "scope-#{scope}",
      event: "scope:#{scope}",
      label: State.scope_label(scope),
      active: scope == current
    }

    ~GPUI"""
    <UI.button id={assigns.id} label={assigns.label} size="xs" variant={if assigns.active, do: "primary", else: "ghost"} phx-click={assigns.event} />
    """
  end

  defp group_chip(group, current) do
    assigns = %{
      id: "group-#{group}",
      event: "group:#{group}",
      label: State.group_label(group),
      active: group == current
    }

    ~GPUI"""
    <UI.button id={assigns.id} label={assigns.label} size="xs" variant={if assigns.active, do: "primary", else: "ghost"} phx-click={assigns.event} />
    """
  end

  defp type_filter_chip(type, types) do
    assigns = %{
      id: "filter-#{type}",
      event: "filter:#{type}",
      label: Classifier.label(type),
      active: MapSet.member?(types, type),
      color: Classifier.color(type)
    }

    ~GPUI"""
    <UI.button id={assigns.id} label={assigns.label} size="xs" variant={if assigns.active, do: "primary", else: "ghost"} phx-click={assigns.event} />
    """
  end

  defp empty_notes(assigns) do
    ~GPUI"""
    <text class="text-[12px] leading-[18px] px-1 pt-2" style={[color: {:theme, :muted}]}>{cond do
      assigns.all_notes == [] and assigns.recorder_status == :ready -> "No notes yet. #{String.capitalize(record_hint(assigns))} and say where you are, then your note, or ⌘N to type one."
      assigns.all_notes == [] -> "No notes yet."
      true -> "Nothing matches here. Widen the scope or clear the filters."
    end}</text>
    """
  end

  defp note_group({key, heading, notes}, state) do
    assigns = %{key: key, heading: heading, notes: notes, state: state}

    ~GPUI"""
    <div id={"group-" <> assigns.key} class="flex flex-col w-full gap-2 pt-1">
      <div class="flex flex-row items-center gap-2 px-1">
        {UIKit.heading(assigns.heading)}
        <text class="text-[10px]" style={[color: {:theme, :muted}]}>{length(assigns.notes)}</text>
      </div>
      {Enum.map(assigns.notes, &note_card(&1, assigns.state))}
    </div>
    """
  end

  defp note_card(%Note{} = note, state) do
    assigns = %{
      note: note,
      selected:
        state.tercet != nil and note.anchor.cantica == state.cantica and
          note.anchor.canto == state.canto and Anchor.tercet_number(note.anchor) == state.tercet,
      deleting: state.pending_delete == note.id,
      playing: state.playing == note.id,
      body: Anchor.strip_phrase(note.text, note.anchor_phrase),
      time:
        Calendar.strftime(note.recorded_at, "%b %-d, %H:%M") <>
          if(note.edited_at, do: " · edited", else: "")
    }

    ~GPUI"""
    <div id={"note-" <> assigns.note.id} class="relative flex flex-col w-full rounded-md px-3 py-2 gap-2"
      style={[background: if(assigns.selected, do: {:theme, :surface}, else: {:theme, :canvas})]}>
      <div class="flex flex-row items-center gap-2">
        <div class="w-[7px] h-[7px] rounded-full" style={[background: {:theme, Classifier.color(assigns.note.type)}]} />
        <text class="text-[11px] font-semibold" style={[color: {:theme, Classifier.color(assigns.note.type)}]}>{Classifier.label(assigns.note.type)}</text>
        <.action id={"jump-" <> assigns.note.id} phx-click={"goto:" <> State.encode(assigns.note.anchor)} accessibility_label="Show in the poem" class="cursor-pointer">
          <text class="text-[11px]" style={[color: {:theme, :accent}]}>{Anchor.label(assigns.note.anchor)}</text>
        </.action>
        <div class="flex-1" />
        <text class="text-[10px]" style={[color: {:theme, :muted}]}>{assigns.time}</text>
      </div>
      <text class="text-[13px] leading-[19px]">{assigns.body}</text>
      <div class="flex flex-row items-center gap-1">
        {if assigns.note.audio, do: play_button(assigns.note.id, assigns.playing), else: []}
        <div class="flex-1" />
        {if assigns.deleting do
          [small_button("note-delete-cancel", "Keep"), id_button("note-delete-confirm:" <> assigns.note.id, "Delete for good", "danger")]
        else
          [id_button("note-edit:" <> assigns.note.id, "Edit", "ghost"), id_button("note-delete:" <> assigns.note.id, "Delete", "ghost")]
        end}
      </div>
    </div>
    """
  end

  defp play_button(id, playing) do
    assigns = %{id: id, playing: playing}

    ~GPUI"""
    <UI.button id={"play-" <> assigns.id} label={if assigns.playing, do: "■ Stop", else: "▶ Play"} size="xs" variant="ghost"
      phx-click={if assigns.playing, do: "stop-clip", else: "play:" <> assigns.id} />
    """
  end

  defp id_button(event, label, variant) do
    assigns = %{id: String.replace(event, ":", "-"), event: event, label: label, variant: variant}

    ~GPUI"""
    <UI.button id={assigns.id} label={assigns.label} size="xs" variant={assigns.variant} phx-click={assigns.event} />
    """
  end

  # -- Command palette ---------------------------------------------------------

  defp palette(assigns) do
    choices = State.choices(assigns)
    highlighted = Enum.at(choices, assigns.palette_index)

    assigns =
      Map.merge(assigns, %{
        choices: choices,
        highlighted: highlighted && "choice-" <> highlighted.event
      })

    ~GPUI"""
    <Overlay.dialog id="palette" open={assigns.palette} title="Go to a canto or run a command" width={520} phx-change="palette-open">
      <:content>
        <div class="flex flex-col gap-2 w-full">
          <UI.input id="palette-search" label="Go to" placeholder="inf 5 · purg 9.70 · record · export…"
            value={assigns.palette_query} focus_request={assigns.palette_focus}
            phx-change="palette-query" phx-submit="palette-submit" />
          <div class="flex flex-col w-full h-[320px]">
            <UI.virtual_list id="palette-results" label="Matching places and commands" selected={assigns.highlighted} reveal={assigns.highlighted}
              item_height={32} phx-change="palette-pick" class="w-full flex-1 min-h-0">
              {Enum.map(assigns.choices, &palette_choice(&1, assigns.highlighted))}
            </UI.virtual_list>
          </div>
          <text class="text-[10px]" style={[color: {:theme, :muted}]}>↑↓ to choose · Enter to run · Escape to dismiss</text>
        </div>
      </:content>
    </Overlay.dialog>
    """
  end

  defp palette_choice(choice, highlighted) do
    assigns = Map.put(choice, :highlighted, "choice-" <> choice.event == highlighted)

    ~GPUI"""
    <UI.virtual_list_item id={"choice-" <> assigns.event} class="flex flex-row items-center w-full h-8 px-2 gap-2"
      style={[background: if(assigns.highlighted, do: {:theme, :surface}, else: {:theme, :canvas})]}>
      <text class="flex-1 text-[12px] truncate">{assigns.label}</text>
      <text class="text-[10px]" style={[color: {:theme, :muted}]}>{assigns.detail}</text>
    </UI.virtual_list_item>
    """
  end

  # -- Status ------------------------------------------------------------------

  defp status_bar(assigns) do
    ~GPUI"""
    <div class="relative flex flex-row items-center h-7 shrink-0 px-4 gap-3">
      {UIKit.rule_top()}
      <text id="status" class="text-[11px]" style={[color: {:theme, :muted}]}>{assigns.status}</text>
      {if assigns.notice, do: notice(assigns.notice, "notice"), else: []}
      <div class="flex-1" />
      <text class="text-[11px]" style={[color: {:theme, :muted}]}>{recorder_label(assigns.recorder_status)}{hotkey_label(assigns)}</text>
      <text class="text-[11px]" style={[color: {:theme, :muted}]}>{selection_label(assigns)}</text>
    </div>
    """
  end

  defp notice(text, id) do
    assigns = %{text: text, id: id}

    ~GPUI"""
    <text id={assigns.id} class="text-[11px]" style={[color: {:theme, :recording}]}>{assigns.text}</text>
    """
  end

  defp hotkey_label(%{hotkey_status: :listening, hotkey: key}),
    do: " · hold #{State.hotkey_name(key)} to talk"

  defp hotkey_label(%{hotkey_status: :denied}), do: " · hold-to-talk needs Input Monitoring"
  defp hotkey_label(_), do: ""

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

  def handle_event("goto:" <> encoded, _event, state),
    do: {:noreply, State.go_to(state, State.decode(encoded))}

  def handle_event("tercet:" <> n, _event, state),
    do: {:noreply, State.select_tercet(state, String.to_integer(n))}

  def handle_event("next-canto", _event, state), do: {:noreply, State.next_canto(state)}
  def handle_event("previous-canto", _event, state), do: {:noreply, State.previous_canto(state)}
  def handle_event("toggle-italian", _event, state), do: {:noreply, State.toggle_italian(state)}

  def handle_event("toggle-theme", _event, state) do
    state = State.toggle_theme(state)

    if Process.whereis(DanteJournal.Display),
      do: GPUI.Display.Native.set_theme(DanteJournal.Display, state.theme)

    {:noreply, state}
  end

  # ⌘Q, the palette, or the window's close button. A dictation in progress
  # is stopped; notes are saved explicitly, so nothing else needs flushing.
  def handle_event("quit", _event, state) do
    if state.recording && state.recorder, do: Recorder.stop_recording(state.recorder)
    {:close, state}
  end

  # Dictation

  def handle_event("toggle-recording", _event, %{recording: nil} = state) do
    cond do
      state.form != nil ->
        {:noreply, %{state | notice: "Save or discard the open note first."}}

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

  # The note card

  def handle_event("new-note", _event, %{form: nil, recording: nil} = state),
    do: {:noreply, State.new_typed_note(state)}

  def handle_event("new-note", _event, state),
    do: {:noreply, %{state | notice: "Finish the open note first."}}

  def handle_event("form-transaction", _event, state), do: {:noreply, state}

  def handle_event("form-text", %{value: text}, state),
    do: {:noreply, State.update_form(state, &Form.change_text(&1, text))}

  def handle_event("form-type:" <> type, _event, state),
    do: {:noreply, State.update_form(state, &Form.set_type(&1, String.to_existing_atom(type)))}

  def handle_event("form-anchor-selection", _event, state) do
    case State.selection_anchor(state) do
      nil -> {:noreply, state}
      anchor -> {:noreply, State.update_form(state, &Form.set_anchor(&1, anchor, :chosen))}
    end
  end

  def handle_event("form-anchor-canto", _event, state),
    do:
      {:noreply,
       State.update_form(state, &Form.set_anchor(&1, State.canto_anchor(state), :chosen))}

  def handle_event(
        "form-anchor-spoken",
        _event,
        %{form: %{spoken_anchor: %Anchor{} = anchor}} = state
      ),
      do: {:noreply, State.update_form(state, &Form.set_anchor(&1, anchor, :spoken))}

  def handle_event("form-anchor-input", %{value: value}, state),
    do: {:noreply, State.update_form(state, &%{&1 | anchor_input: value})}

  def handle_event("form-anchor-apply", %{value: value}, state),
    do: {:noreply, State.update_form(state, &Form.apply_anchor_input(&1, value, state))}

  def handle_event("form-save", _event, state), do: {:noreply, State.save_form(state)}
  def handle_event("form-discard", _event, state), do: {:noreply, State.discard_form(state)}

  # Notes pane

  def handle_event("note-edit:" <> id, _event, %{form: nil} = state),
    do: {:noreply, State.edit_note(state, id)}

  def handle_event("note-edit:" <> _id, _event, state),
    do: {:noreply, %{state | notice: "Finish the open note first."}}

  def handle_event("note-delete:" <> id, _event, state),
    do: {:noreply, State.request_delete(state, id)}

  def handle_event("note-delete-cancel", _event, state),
    do: {:noreply, %{state | pending_delete: nil}}

  def handle_event("note-delete-confirm:" <> id, _event, state),
    do: {:noreply, State.delete_note(state, id)}

  def handle_event("play:" <> id, _event, %{player: player} = state) when not is_nil(player) do
    case Enum.find(state.all_notes, &(&1.id == id)) do
      %Note{audio: audio} when is_binary(audio) ->
        Player.play(
          player,
          id,
          Path.join(Path.dirname(Notes.clip_path(state.notes, id)) |> Path.dirname(), audio)
        )

        {:noreply, state}

      _ ->
        {:noreply, %{state | notice: "No audio clip for this note."}}
    end
  end

  def handle_event("play:" <> _id, _event, state), do: {:noreply, state}

  def handle_event("stop-clip", _event, %{player: player} = state) when not is_nil(player) do
    Player.stop(player)
    {:noreply, state}
  end

  def handle_event("scope:" <> scope, _event, state),
    do: {:noreply, State.set_scope(state, String.to_existing_atom(scope))}

  def handle_event("group:" <> group, _event, state),
    do: {:noreply, State.set_group(state, String.to_existing_atom(group))}

  def handle_event("filter:" <> type, _event, state),
    do: {:noreply, State.toggle_type_filter(state, String.to_existing_atom(type))}

  def handle_event("notes-clear-filters", _event, state),
    do: {:noreply, State.clear_filters(state)}

  def handle_event("notes-query", %{value: value}, state),
    do: {:noreply, State.set_query(state, value)}

  def handle_event("focus-search", _event, state),
    do: {:noreply, %{state | notes_search_focus: state.notes_search_focus + 1}}

  def handle_event("export-copied", _event, state),
    do: {:noreply, %{state | notice: "Markdown copied."}}

  def handle_event("export:" <> kind, _event, state) do
    notes = State.visible_notes(state)
    title = State.export_title(state)

    {content, extension} =
      case kind do
        "md" -> {Export.markdown(notes, state.english, title), "md"}
        _ -> {Export.text(notes, state.english, title), "txt"}
      end

    case Export.write(content, extension, State.export_slug(state)) do
      {:ok, path} ->
        Export.reveal(path)
        {:noreply, %{state | notice: "Saved #{Path.basename(path)} in Documents/Dante Journal."}}

      {:error, reason} ->
        {:noreply, %{state | notice: "Couldn't export: #{inspect(reason)}"}}
    end
  end

  # Palette

  def handle_event("hotkey:" <> key, _event, state),
    do: {:noreply, State.set_hotkey(state, String.to_integer(key))}

  def handle_event("hotkey-learn", _event, state), do: {:noreply, State.learn_hotkey(state)}

  def handle_event("english:" <> english, _event, state),
    do: {:noreply, State.set_english(state, String.to_existing_atom(english))}

  def handle_event("open-palette", _event, state), do: {:noreply, State.open_palette(state)}

  def handle_event("palette-open", %{value: open}, state),
    do: {:noreply, if(open, do: state, else: State.close_palette(state))}

  def handle_event("palette-query", %{value: value}, state),
    do: {:noreply, %{state | palette_query: value, palette_index: 0}}

  def handle_event("palette-key", %{value: key}, state) when key in ["down", "up"] do
    last = max(length(State.choices(state)) - 1, 0)
    step = if key == "down", do: 1, else: -1
    {:noreply, %{state | palette_index: (state.palette_index + step) |> max(0) |> min(last)}}
  end

  def handle_event("palette-key", %{value: key}, state) when key in ["enter", "\r", "\n"],
    do: handle_event("palette-submit", %{}, state)

  def handle_event("palette-key", _event, state), do: {:noreply, state}

  # Enter carries the input's current text; trust it over the last change
  # event, which can lag or be missing, so the highlighted choice is the one
  # the user is looking at and never the first of an unfiltered list.
  def handle_event("palette-submit", event, state) do
    state =
      case event do
        %{value: value} when is_binary(value) and value != state.palette_query ->
          %{state | palette_query: value, palette_index: 0}

        _ ->
          state
      end

    case Enum.at(State.choices(state), state.palette_index) do
      nil -> {:noreply, state}
      choice -> handle_event(choice.event, %{}, State.close_palette(state))
    end
  end

  def handle_event("palette-pick", %{value: "choice-" <> event}, state),
    do: handle_event(event, %{}, State.close_palette(state))

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
     State.form_from_transcript(state, text, %{
       id: recording.id,
       clip: result.clip || recording.clip,
       ms: result.ms || 0
     })}
  end

  def handle_info({:recorder, {:transcript, %{text: text}}}, state),
    do: {:noreply, State.form_from_transcript(state, text, %{})}

  def handle_info({:recorder, {:error, message}}, state),
    do: {:noreply, %{state | recording: nil, notice: message}}

  def handle_info({:recorder, {:hotkey, {:listening, key}}}, state),
    do: {:noreply, %{state | hotkey_status: :listening, hotkey: key}}

  def handle_info({:recorder, {:hotkey, {:learned, key}}}, state),
    do: {:noreply, State.learned_hotkey(state, key)}

  def handle_info({:recorder, {:hotkey, :denied}}, state) do
    {:noreply,
     %{
       state
       | hotkey_status: :denied,
         notice:
           "Hold-to-talk needs Input Monitoring: System Settings → Privacy & Security → Input Monitoring, then relaunch."
     }}
  end

  # Press starts; release stops if it was held, while a quick tap leaves the
  # dictation running so the key also works as a toggle.
  def handle_info({:recorder, {:hotkey, :down}}, %{recording: nil} = state) do
    {:noreply, state} = handle_event("toggle-recording", %{}, state)
    {:noreply, %{state | hotkey_down_at: System.monotonic_time(:millisecond)}}
  end

  def handle_info({:recorder, {:hotkey, :down}}, state),
    do: handle_event("toggle-recording", %{}, state)

  def handle_info({:recorder, {:hotkey, :up}}, %{recording: %{}, hotkey_down_at: at} = state)
      when is_integer(at) do
    if System.monotonic_time(:millisecond) - at >= 400,
      do: handle_event("toggle-recording", %{}, %{state | hotkey_down_at: nil}),
      else: {:noreply, %{state | hotkey_down_at: nil}}
  end

  def handle_info({:recorder, {:hotkey, :up}}, state),
    do: {:noreply, %{state | hotkey_down_at: nil}}

  def handle_info({:player, {:playing, id}}, state), do: {:noreply, %{state | playing: id}}
  def handle_info({:player, :stopped}, state), do: {:noreply, %{state | playing: nil}}

  def handle_info({:player, {:error, message}}, state),
    do: {:noreply, %{state | playing: nil, notice: message}}

  def handle_info(_message, state), do: {:noreply, state}
end
