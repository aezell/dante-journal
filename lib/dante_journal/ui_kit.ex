defmodule DanteJournal.UIKit do
  @moduledoc "The few treatments every pane shares, so new panes read like the old ones."
  import GPUI.Template, only: [sigil_GPUI: 2]

  @doc "A clickable region that is announced as a button."
  def action(assigns) do
    {children, attrs} = Map.pop(assigns, :children, [])

    %GPUI.Element{
      type: :div,
      attrs: Map.to_list(Map.put(attrs, :accessibility_role, "button")),
      children: children
    }
  end

  @doc "A one-pixel horizontal rule along the bottom of a relative parent."
  def rule do
    ~GPUI"""
    <div class="absolute bottom-0 left-0 w-full h-[1px]" style={[background: {:theme, :border}]} />
    """
  end

  @doc "A one-pixel horizontal rule along the top of a relative parent."
  def rule_top do
    ~GPUI"""
    <div class="absolute top-0 left-0 w-full h-[1px]" style={[background: {:theme, :border}]} />
    """
  end

  @doc "A one-pixel vertical rule along the right edge of a relative parent."
  def vertical_rule do
    ~GPUI"""
    <div class="absolute top-0 bottom-0 right-0 w-[1px]" style={[background: {:theme, :border}]} />
    """
  end

  @doc "A muted section heading."
  def heading(label) do
    assigns = %{label: label}

    ~GPUI"""
    <text class="text-[11px] font-semibold" style={[color: {:theme, :muted}]}>{assigns.label}</text>
    """
  end
end
