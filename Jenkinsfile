#!/usr/bin/groovy

// def call() {

// Check for a previous build and cancel
def buildNumber = env.BUILD_NUMBER as int
  if (buildNumber > 1) milestone(buildNumber - 1)
  milestone(buildNumber)

  def buildResult = 'PENDING'
  String description = 'test using nrel/openstudio:3.6.1'
  String context = 'nrel/openstudio:3.6.1'
  // GitHUb Notifcation here.  Until the github plugin is fixed. See https://issues.jenkins-ci.org/browse/JENKINS-54249'
  // It sucks that you don't have a way to mark a status as "Skipped", but if we defer the creation of the status after Skip CI is checked, then you won't get any status on the PR
  // letting you know that the build is actually pending and with a link to go check on Jenkins. And that can take several hours for the windows instance.
  githubNotify description: "${description}",  context: "${context}", status: "${buildResult}" , credentialsId: 'ci-commercialbuildings-test'

  node('nrel_docker_vcpu80') {
    String linux_base = '/srv/data/jenkins/git'

    dir("${linux_base}/${env.JOB_NAME}/${env.BUILD_NUMBER}") {
      // clear dir if previous contents
      deleteDir()

      checkout scm

      echo 'running in docker image nrel/openstudio:3.6.1'
      docker.image('nrel/openstudio:3.6.1').inside('-u root -e "LANG=en_US.UTF-8"') {
        sh('locale-gen en_US.UTF-8')

        stage('show enviroment') {
          try {
          sh('ruby -v')
          sh('openstudio openstudio_version')
          }
          catch (Exception e) {
          e.printStackTrace()
          buildResult = 'FAILURE'
          description = "${description} - CI Setup Failures"
          }
        }

      stage('install dependencies') {
          try {
          sh("gem install bundler -v '2.1.4'")
          sh("pwd") 
          sh '''
          export GEM_PATH="/var/oscli/gems/ruby/2.7.0"
          unset BUNDLE_WITHOUT
          bundle config set git.allow_insecure true
          bundle config set path /var/oscli/gems
          '''
          sh('bundle install --gemfile ./resources/Gemfile')
          }
          catch (Exception e) {
          e.printStackTrace()
          buildResult = 'FAILURE'
          description = "${description} - Bundle Install Failed"
          error 'Bundle install failed. check logs'
          }
      }

        stage('run measure tests') {
          try {
          timeout(time: 600, unit: 'MINUTES') {
              sh '''
              bundle config set without 'native_ext'
              cd ./resources/
              bundle exec rake unit_tests:measure_tests
              '''
          }
          }
          catch (Exception e) {
          e.printStackTrace()
          buildResult = 'FAILURE'
          description = "${description} - Test Failures"
          }
          finally {
          try {
            archiveArtifacts artifacts: '../test/report/', fingerprint: true
            junit '../test/report/*.xml'
          }
            catch (Exception e) {
            buildResult = 'FAILURE'
            description = "${description} - Artifact Download Failures"
            e.printStackTrace()
            }
          }
        }

        // docker user is root so all file permissions need to be changed for jenkins to cleanup
        sh "chmod -R 777 ${linux_base}/${env.JOB_NAME}/${env.BUILD_NUMBER}"
      }
      // cleanup workspace
      deleteDir()

      // Notify github of result
      if ((buildResult != 'FAILURE') && (buildResult != 'ERROR')) {
      buildResult = 'SUCCESS'
      }
      githubNotify description: "${description}",  context: "${context}", status: "${buildResult}" , credentialsId: 'ci-commercialbuildings-test'
      currentBuild.result = "${buildResult}"
    }
  }
// }
// call()
