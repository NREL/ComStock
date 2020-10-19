# ComStock™, Copyright (c) 2020 Alliance for Sustainable Energy, LLC. All rights reserved.
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

module OsLib_QAQC
  # Check the calibration against utility bills.
  def check_calibration(category, target_standard, max_nmbe, max_cvrmse, name_only = false)
    # summary of the check
    check_elems = OpenStudio::AttributeVector.new
    check_elems << OpenStudio::Attribute.new('name', 'Calibration')
    check_elems << OpenStudio::Attribute.new('category', category)
    check_elems << OpenStudio::Attribute.new('description', 'Check that the model is calibrated to the utility bills.')

    # stop here if only name is requested this is used to populate display name for arguments
    if name_only == true
      results = []
      check_elems.each do |elem|
        results << elem.valueAsString
      end
      return results
    end

    std = Standard.build(target_standard)

    begin
      # Check that there are utility bills in the model
      if @model.getUtilityBills.empty?
        check_elems << OpenStudio::Attribute.new('flag', 'Model contains no utility bills, cannot check calibration.')
      end

      # Check the calibration for each utility bill
      @model.getUtilityBills.each do |bill|
        bill_name = bill.name.get
        fuel = bill.fuelType.valueDescription

        # Consumption

        # NMBE
        if bill.NMBE.is_initialized
          nmbe = bill.NMBE.get
          if nmbe > max_nmbe || nmbe < -1.0 * max_nmbe
            check_elems << OpenStudio::Attribute.new('flag', "For the #{fuel} bill called #{bill_name}, the consumption NMBE of #{nmbe.round(1)}% is outside the limit of +/- #{max_nmbe}%, so the model is not calibrated.")
          end
        end

        # CVRMSE
        if bill.CVRMSE.is_initialized
          cvrmse = bill.CVRMSE.get
          if cvrmse > max_cvrmse
            check_elems << OpenStudio::Attribute.new('flag', "For the #{fuel} bill called #{bill_name}, the consumption CVRMSE of #{cvrmse.round(1)}% is above the limit of #{max_cvrmse}%, so the model is not calibrated.")
          end
        end

        # Peak Demand (for some fuels)
        if bill.peakDemandUnitConversionFactor.is_initialized
          peak_conversion = bill.peakDemandUnitConversionFactor.get

          # Get modeled and actual values
          actual_vals = []
          modeled_vals = []
          bill.billingPeriods.each do |billing_period|
            actual_peak = billing_period.peakDemand
            if actual_peak.is_initialized
              actual_vals << actual_peak.get
            end

            modeled_peak = billing_period.modelPeakDemand
            if modeled_peak.is_initialized
              modeled_vals << modeled_peak.get
            end
          end

          # Check that both arrays are the same size
          unless actual_vals.size == modeled_vals.size
            check_elems << OpenStudio::Attribute.new('flag', "For the #{fuel} bill called #{bill_name}, cannot get the same number of modeled and actual peak demand values, cannot check peak demand calibration.")
          end

          # NMBE and CMRMSE
          ysum = 0
          sum_err = 0
          squared_err = 0
          n = actual_vals.size

          actual_vals.each_with_index do |actual, i|
            modeled = modeled_vals[i]
            actual *= peak_conversion # Convert actual demand to model units
            ysum += actual
            sum_err += (actual - modeled)
            squared_err += (actual - modeled)**2
          end

          if n > 1
            ybar = ysum / n

            # NMBE
            demand_nmbe = 100.0 * (sum_err / (n - 1)) / ybar
            if demand_nmbe > max_nmbe || demand_nmbe < -1.0 * max_nmbe
              check_elems << OpenStudio::Attribute.new('flag', "For the #{fuel} bill called #{bill_name}, the peak demand NMBE of #{demand_nmbe.round(1)}% is outside the limit of +/- #{max_nmbe}%, so the model is not calibrated.")
            end

            # CVRMSE
            demand_cvrmse = 100.0 * (squared_err / (n - 1))**0.5 / ybar
            if demand_cvrmse > max_cvrmse
              check_elems << OpenStudio::Attribute.new('flag', "For the #{fuel} bill called #{bill_name}, the peak demand CVRMSE of #{demand_cvrmse.round(1)}% is above the limit of #{max_cvrmse}%, so the model is not calibrated.")
            end
          end

        end
      end
    rescue StandardError => e
      # brief description of ruby error
      check_elems << OpenStudio::Attribute.new('flag', "Error prevented QAQC check from running (#{e}).")

      # backtrace of ruby error for diagnostic use
      if @error_backtrace then check_elems << OpenStudio::Attribute.new('flag', e.backtrace.join("\n").to_s) end
    end

    # add check_elms to new attribute
    check_elem = OpenStudio::Attribute.new('check', check_elems)

    return check_elem
    # note: registerWarning and registerValue will be added for checks downstream using os_lib_reporting_qaqc.rb
  end
end
