# frozen_string_literal: true

# @type self: Rake::TaskLib

# load rake tasks from tasks directory
if RUBY_VERSION.start_with?("1.8.")
  import File.join(File.dirname(__FILE__) || Dir.pwd, "tasks", "test.rake")
else
  Dir.glob(File.join(File.dirname(__FILE__) || Dir.pwd, "tasks", "**", "*.rake")) { |f| import f }
end
