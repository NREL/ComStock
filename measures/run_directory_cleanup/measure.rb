# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.
require 'fileutils'

# start the measure
class RunDirectoryCleanup < OpenStudio::Measure::ReportingMeasure
  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    "Run Directory Cleanup"
  end

  # define the arguments that the user will input
  def arguments(model = nil)
    args = OpenStudio::Ruleset::OSArgumentVector.new
  end # end the arguments method

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # use the built-in error checking
    unless runner.validateUserArguments(arguments, user_arguments)
      false
    end

    # Specify file patterns to delete
    del_patterns = [
      # Top-level files
      "./../*.epw",
      "./../*.sql",
      "./../*.audit",
      "./../*.bnd",
      "./../*.eio",
      "./../*.shd",
      "./../*.mdd",
      "./../*.eso",
      "./../pre-preprocess.idf",
      "./../*.end",
      "./../*.mtd",
      "./../eplusssz.csv",
      "./../*.mtr",
      "./../*.rvi",
      "./../convert.txt",
      "./../convertESOMTR*",
      "./../ReadVarsESO*",
      "./../data_point.zip",
      # Sizing run files
      "./../**/*SR*/**/*.epw",
      "./../**/*SR*/**/*.sql",
      "./../**/*SR*/**/*.audit",
      "./../**/*SR*/**/*.bnd",
      "./../**/*SR*/**/*.eio",
      "./../**/*SR*/**/*.shd",
      "./../**/*SR*/**/*.mdd",
      "./../**/*SR*/**/*.eso",
      "./../**/*SR*/**/pre-preprocess.idf",
      "./../**/*SR*/**/*.end",
      "./../**/*SR*/**/*.mtd",
      "./../**/*SR*/**/eplusssz.csv",
      "./../**/*SR*/**/*.mtr",
      "./../**/*SR*/**/*.rvi",
      "./../**/*SR*/**/convert.txt",
      "./../**/*SR*/**/convertESOMTR*",
      "./../**/*SR*/**/ReadVarsESO*",
      "./../**/*SR*/**/data_point.zip"
    ]

    # Delete files
    del_patterns.each do |del_pattern|
      Dir.glob(del_pattern).each do |f|
        File.delete(f)
        runner.registerInfo("Deleted file #{f} from the run directory.") unless File.exist?(f)
      end
    end

    return true
  end # end the run method
end # end the measure

# this allows the measure to be use by the application
RunDirectoryCleanup.new.registerWithApplication
