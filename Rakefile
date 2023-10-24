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

    t.test_files = FileList['measures/qoi_report/tests/*.rb']
    t.verbose = true
    t.warning = false
  end

  task :build do

    ENV.each do |k, v|
      puts "#{k} : #{v}"
    end
  end
end
