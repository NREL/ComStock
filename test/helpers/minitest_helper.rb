require 'minitest/autorun'
require 'minitest/reporters'
require 'json'


if ENV['JENKINS_HOME']
  Minitest::Reporters.use! [Minitest::Reporters::JUnitReporter.new(reports_dir = "test/reports2", empty = true)]
end
