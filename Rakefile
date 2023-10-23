require 'rake'
require 'rake/testtask'
require 'minitest/reporters'  # Require the gem

# Configure the JUnit reporter
Minitest::Reporters.use! [Minitest::Reporters::JUnitReporter.new]

desc 'Perform tasks related to unit tests'
namespace :unit_tests do
  desc 'Run all measure tests'
  Rake::TestTask.new('measure_tests') do |t|
    t.test_files = FileList['measures/qoi_report/tests/*.rb', 'measures/la_100_qaqc/tests/*.rb']
    t.verbose = false
    t.warning = false
    t.options = '--junit --junit-jenkins --junit-filename=./test/report.xml'
  end
end
