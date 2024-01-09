//Jenkins pipelines are stored in shared libaries. Please see: https://github.com/NREL/cbci_jenkins_libs

@Library('cbci_shared_libs') _


// Build for PR to main branch only.
if ((env.CHANGE_ID) && (env.CHANGE_TARGET == "main") ) {
    building_comstock_all()
}
