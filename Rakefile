require 'rake'
require 'rake/testtask'
require 'minitest/reporters'  # Require the gem

# Configure the JUnit reporter

desc 'Perform tasks related to unit tests'
namespace :unit_tests do
  desc 'Run measure tests'
  Rake::TestTask.new('measure_tests') do |t|
    MEASURETESTS_PATH = "test/measure_tests.txt"
    if File.exist?(MEASURETESTS_PATH)
      # load test files from file.
      full_file_list = FileList.new(File.readlines(MEASURETESTS_PATH).map(&:chomp))
      full_file_list.select! { |item| item.include?('rb')}
      p full_file_list

    end
    t.test_files = full_file_list
    p(full_file_list)
    t.verbose = false
    t.warning = false
  end

  Rake::TestTask.new('resource_measure_tests') do |t|
    RESOURCE_MEASURETESTS_PATH = "test/resource_measure_tests.txt"
    if File.exist?(RESOURCE_MEASURETESTS_PATH)
      # load test files from file.
      full_file_list = FileList.new(File.readlines(RESOURCE_MEASURETESTS_PATH).map(&:chomp))
      full_file_list.select! { |item| item.include?('rb')}
      p full_file_list
    end
    t.test_files = full_file_list
    p(full_file_list)
    t.verbose = false
    t.warning = false
  end

end
