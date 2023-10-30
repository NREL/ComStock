require 'rake'
require 'rake/testtask'
require 'minitest/reporters'  # Require the gem

# Configure the JUnit reporter
# Minitest::Reporters.use! [Minitest::Reporters::JUnitReporter.new(reports_dir = "reports/", empty = false, options = {})]

desc 'Perform tasks related to unit tests'
namespace :unit_tests do
  desc 'Run all measure tests'
  # ENV['MINITEST_REPORTER'] = 'JUnitReporter'
  Rake::TestTask.new('measure_tests') do |t|
    MEASURETESTS_PATH = "test/measure_tests.txt"
    # p File.exist?(MEASURETESTS_PATH)
    if File.exist?(MEASURETESTS_PATH)
      # load test files from file.
      full_file_list = FileList.new(File.readlines(MEASURETESTS_PATH).map(&:chomp))
      full_file_list.select! { |item| item.include?('rb')}
      # Select only .rb files that exist
      p full_file_list

    end
    t.test_files = full_file_list
    p(full_file_list)

    t.verbose = false
    t.warning = false
  end
end
