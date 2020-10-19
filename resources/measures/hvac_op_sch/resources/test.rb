# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.


require 'openstudio'
require_relative 'Standards.ScheduleRuleset'

#load a model into OS & version translates, exiting and erroring if a problem is found
def safe_load_model(model_path_string)  
  model_path = OpenStudio::Path.new(model_path_string)
  if OpenStudio::exists(model_path)
    versionTranslator = OpenStudio::OSVersion::VersionTranslator.new 
    model = versionTranslator.loadModel(model_path)
    if model.empty?
      puts "Version translation failed for #{model_path_string}"
      exit
    else
      model = model.get
    end
  else
    puts "#{model_path_string} couldn't be found"
    exit
  end
  return model
end

model = safe_load_model("C:/GitRepos/OpenStudio-PTool/measures/hvac_correct_operations_schedule/tests/LargeOffice-90.1-2010-ASHRAE 169-2006-5A.osm")

#sch = model.getScheduleRulesetByName("OfficeLarge BLDG_OCC_SCH").get
sch = model.getScheduleRulesetByName("OfficeLarge HVACOperationSchd").get
puts sch.class
puts sch.annual_equivalent_full_load_hrs


