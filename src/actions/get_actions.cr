require "./base.cr"
require "./clear_action.cr"
require "./help_action.cr"
require "./live_action.cr"
require "./playback_actions.cr"
require "./replay_action.cr"
require "./stlats_action.cr"

def get_actions : Hash(String, Action)
  actions = [
    ReplayAction.new,
    PauseAction.new,
    ResumeAction.new,
    HelpAction.new,
    LiveAction.new,
    StlatsAction.new,
    ClearAction.new,
  ]

  actions_by_aliases = actions
    .flat_map { |action| action.aliases.map { |s| {s, action} } }
    .to_h

  pp actions_by_aliases

  return actions_by_aliases
end
