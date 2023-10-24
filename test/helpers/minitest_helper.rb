require 'minitest/autorun'
require 'minitest/reporters'
Minitest::Reporters.use! [Minitest::Reporters::JUnitReporter.new(reports_dir = "test/reports2", empty = true)]
