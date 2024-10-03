require 'rake'
require 'rake/testtask'
require 'minitest/reporters'  # Require the gem

# Configure the JUnit reporter

desc 'Perform tasks related to unit tests'
namespace :unit_tests do
  desc 'Run measure tests'
  Rake::TestTask.new('measure_tests') do |t|
    measure_tests_path = 'test/measure_tests.txt'
    if File.exist?(measure_tests_path)
      # load test files from file.
      full_file_list = FileList.new(File.readlines(measure_tests_path).map(&:chomp))
      full_file_list.select! { |item| item.include?('rb') }
      p full_file_list

    end
    t.test_files = full_file_list
    p(full_file_list)
    t.verbose = false
    t.warning = false
  end

  Rake::TestTask.new('resource_measure_tests') do |t|
    resource_measure_tests_path = 'test/resource_measure_tests.txt'
    if File.exist?(resource_measure_tests_path)
      # load test files from file.
      full_file_list = FileList.new(File.readlines(resource_measure_tests_path).map(&:chomp))
      full_file_list.select! { |item| item.include?('rb') && File.exist?(item) }
      p full_file_list
    end
    t.test_files = full_file_list.select do |file|
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
    p(full_file_list)
    t.verbose = false
    t.warning = false
  end
end

# run rubocop
require 'rubocop/rake_task'
desc 'Check the code for style consistency'
RuboCop::RakeTask.new(:rubocop) do |t|
  # Make a folder for the output
  out_dir = '.rubocop'
  FileUtils.mkdir_p(out_dir)
  # Output both XML (CheckStyle format) and HTML
  t.options = ["--out=#{out_dir}/rubocop-results.xml", '--format=h', "--out=#{out_dir}/rubocop-results.html", '--format=offenses', "--out=#{out_dir}/rubocop-summary.txt"]
  t.requires = ['rubocop/formatter/checkstyle_formatter']
  t.formatters = ['RuboCop::Formatter::CheckstyleFormatter']
  # don't abort rake on failure
  t.fail_on_error = false
end
