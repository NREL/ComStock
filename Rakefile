require 'rake/testtask'
require 'minitest/reporters'  # Require the gem
require 'parallel'

# Configure the JUnit reporter

desc 'Perform tasks related to unit tests'
namespace :unit_tests do
  desc 'Run measure tests'
  task :measure_tests do
      MEASURETESTS_PATH = "test/measure_tests.txt"
      if File.exist?(MEASURETESTS_PATH)
        # load test files from file.
        full_file_list = FileList.new(File.readlines(MEASURETESTS_PATH).map(&:chomp))
        full_file_list.select! { |item| item.include?('rb')}
      end
      Parallel.each(full_file_list, in_processes: Parallel.processor_count) do |file|
        begin
          # Try to load the file to check for syntax errors
          load file
          true
        rescue Exception => e
          puts "Error in #{file}: #{e.message}"
          Minitest::Reporters.reporter.report_error(file, e)
          false
        end
    end
  end

  desc 'Run resource measure tests'
  task :resource_measure_tests do
      p "resource measure tests"
      RESOURCE_MEASURETESTS_PATH = "test/resource_measure_tests.txt"
      if File.exist?(RESOURCE_MEASURETESTS_PATH)
        # load test files from file.
        full_file_list = FileList.new(File.readlines(RESOURCE_MEASURETESTS_PATH).map(&:chomp))
        full_file_list.select! { |item| item.include?('rb')  && File.exist?(item) }
      end
      Parallel.each(full_file_list, in_processes: Parallel.processor_count) do |file|
        begin
          puts "Processing #{file} in process #{Process.pid}"
          # Try to load the file to check for syntax errors
          load file
          true
        rescue Exception => e
          puts "Error in #{file}: #{e.message}"
          Minitest::Reporters.reporter.report_error(file, e)
          false
        end
    end
  end
end
