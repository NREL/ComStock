# ComStock™, Copyright (c) 2023 Alliance for Sustainable Energy, LLC. All rights reserved.
# See top level LICENSE.txt file for license terms.

# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2018, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# UNITED STATES GOVERNMENT, OR THE UNITED STATES DEPARTMENT OF ENERGY, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

require 'json'

module OsLib_Reporting
  # setup - get model, sql, and setup web assets path
  def self.setup(runner)
    results = {}

    # get the last model
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError('Cannot find last model.')
      return false
    end
    model = model.get

    # get the last idf
    workspace = runner.lastEnergyPlusWorkspace
    if workspace.empty?
      runner.registerError('Cannot find last idf file.')
      return false
    end
    workspace = workspace.get

    # get the last sql file
    sqlFile = runner.lastEnergyPlusSqlFile
    if sqlFile.empty?
      runner.registerError('Cannot find last sql file.')
      return false
    end
    sqlFile = sqlFile.get
    model.setSqlFile(sqlFile)

    # populate hash to pass to measure
    results[:model] = model
    # results[:workspace] = workspace
    results[:sqlFile] = sqlFile
    results[:web_asset_path] = OpenStudio.getSharedResourcesPath / OpenStudio::Path.new('web_assets')

    return results
  end

  # cleanup - prep html
  def self.gen_html(html_in_path, web_asset_path, sections, name)
    # instance variables for erb
    @sections = sections
    @name = name

    # read in template
    if File.exist?(html_in_path)
      html_in_path = html_in_path
    else
      html_in_path = "#{File.dirname(__FILE__)}/report.html.erb"
    end
    html_in = ''
    File.open(html_in_path, 'r') do |file|
      html_in = file.read
    end

    # configure template with variable values
    renderer = ERB.new(html_in)
    html_out = renderer.result(binding)

    # write html file
    html_out_path = './report.html'
    File.open(html_out_path, 'w') do |file|
      file << html_out
      # make sure data is written to the disk one way or the other
      begin
        file.fsync
      rescue StandardError
        file.flush
      end
    end

    return html_out_path
  end

  # developer notes
  # method below is custom version of standard OpenStudio results methods. It passes an array of sections vs. a single section.
  # It doesn't use the model or SQL file. It just gets data form OpenStudio attributes passed in
  # It doesn't have a name_only section since it doesn't populate user arguments

  def self.sections_from_check_attributes(check_elems, runner)
    # inspecting check attributes
    # make single table with checks.
    # make second table with flag description (with column for where it came from)

    # array to hold sections
    sections = []

    # gather data for section
    qaqc_check_summary = {}
    qaqc_check_summary[:title] = 'List of Checks in Measure'
    qaqc_check_summary[:header] = ['Name', 'Category', 'Flags', 'Description']
    qaqc_check_summary[:data] = []
    qaqc_check_summary[:data_color] = []
    @qaqc_check_section = {}
    @qaqc_check_section[:title] = 'QAQC Check Summary'
    @qaqc_check_section[:tables] = [qaqc_check_summary]

    # add sections to array
    sections << @qaqc_check_section

    # counter for flags thrown
    num_flags = 0

    check_elems.each do |check|
      # gather data for section
      qaqc_flag_details = {}
      qaqc_flag_details[:title] = "List of Flags Triggered for #{check.valueAsAttributeVector.first.valueAsString}."
      qaqc_flag_details[:header] = ['Flag Detail']
      qaqc_flag_details[:data] = []
      @qaqc_flag_section = {}
      @qaqc_flag_section[:title] = check.valueAsAttributeVector.first.valueAsString.to_s
      @qaqc_flag_section[:tables] = [qaqc_flag_details]

      check_name = nil
      check_cat = nil
      check_desc = nil
      flags = []
      # loop through attributes (name,category,description,then optionally one or more flag attributes)
      check.valueAsAttributeVector.each_with_index do |value, index|
        if index == 0
          check_name = value.valueAsString
        elsif index == 1
          check_cat = value.valueAsString
        elsif index == 2
          check_desc = value.valueAsString
        else # should be flag
          flags << value.valueAsString
          qaqc_flag_details[:data] << [value.valueAsString]
          runner.registerWarning("#{check_name} - #{value.valueAsString}")
          num_flags += 1
        end
      end

      # add row to table for this check
      qaqc_check_summary[:data] << [check_name, check_cat, flags.size, check_desc]

      # add info message for check if no flags found (this way user still knows what ran)
      if check.valueAsAttributeVector.size < 4
        runner.registerInfo("#{check_name} - no flags.")
      end

      # color cells based and add runner register values based on flag status
      if !flags.empty?
        qaqc_check_summary[:data_color] << ['', '', 'indianred', '']
        runner.registerValue(check_name.downcase.tr(' ', '_'), flags.size, 'flags')
      else
        qaqc_check_summary[:data_color] << ['', '', 'lightgreen', '']
        runner.registerValue(check_name.downcase.tr(' ', '_'), flags.size, 'flags')
      end

      # add table for this check if there are flags
      if !qaqc_flag_details[:data].empty?
        sections << @qaqc_flag_section
      end
    end

    # add total flags registerValue
    runner.registerValue('total_qaqc_flags', num_flags, 'flags')

    return sections
  end
end
