# frozen_string_literal: true

# @type self: Rake::DSL

begin
  require "minitest/test_task"
rescue LoadError
  # Backport "minitest/test_task" for minitest 5.15.0 and down
  if RUBY_VERSION.start_with?("1.8.")
    # Ruby 1.8.7 has no `require_relative`
    require File.expand_path(File.join(File.dirname(__FILE__), "../vendor/minitest/test_task.1.8.rb"))
  else
    require_relative "../vendor/minitest/test_task"
  end
end

Minitest::TestTask.create(:test) do |t|
  t.warning = false
  t.test_globs = ["test/**/test_*.rb"]
end
