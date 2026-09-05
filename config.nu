# opencode runtime flags (pinned 1.18.5): background subagents via `task`
# background:true, parallel tool calls, native question tool, references.
# Set here (not home.sessionVariables): shell-launched opencode only inherits
# $env from nu, and HM doesn't export sessionVariables into nu.
$env.OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS = "true"
$env.OPENCODE_ENABLE_PARALLEL = "true"
$env.OPENCODE_ENABLE_QUESTION_TOOL = "true"
$env.OPENCODE_EXPERIMENTAL_REFERENCES = "true"

$env.config = {
  show_banner: false

  completions: {
    algorithm: fuzzy
    case_sensitive: false
    quick: true
    partial: true
  }

  history: {
    max_size: 100_000
    sync_on_enter: true
    file_format: "sqlite"
    isolation: false
  }

  edit_mode: emacs

  table: {
    mode: rounded
    index_mode: auto
    trim: {
      methodology: wrapping
      wrapping_try_keep_words: true
    }
  }

  datetime_format: {
    normal: "%Y-%m-%d %H:%M:%S"
    table: "%Y-%m-%d"
  }

  menus: [
    # Primary completion menu — bordered, shows up on Tab
    {
      name: completion_menu
      only_buffer_difference: false
      marker: "| "
      type: {
        layout: columnar
        columns: 1
        col_width: 40
        col_padding: 2
      }
      style: {
        text: green
        selected_text: { attr: r }
        description_text: yellow
        match_text: { attr: u }
        selected_match_text: { attr: ur }
      }
    }
    # Description menu — triggered with F1, shows a preview pane
    {
      name: description_menu
      only_buffer_difference: false
      marker: "? "
      type: {
        layout: description
        columns: 1
        col_width: 40
        col_padding: 2
        selection_rows: 10
        description_rows: 10
      }
      style: {
        text: green
        selected_text: { attr: r }
        description_text: yellow
        match_text: { attr: u }
        selected_match_text: { attr: ur }
      }
    }
  ]

  keybindings: [
    {
      name: completion_menu
      modifier: none
      keycode: tab
      mode: [emacs vi_normal vi_insert]
      event: {
        until: [
          { send: menu name: completion_menu }
          { send: menunext }
          { edit: complete }
        ]
      }
    }
    {
      name: description_menu
      modifier: none
      keycode: f1
      mode: [emacs vi_normal vi_insert]
      event: { send: menu name: description_menu }
    }
  ]
}
