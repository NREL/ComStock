#!/usr/bin/groovy

/* groovylint-disable LineLength */

// Check for a previous build and cancel
def buildNumber = env.BUILD_NUMBER as int
if (buildNumber > 1) {
    milestone(buildNumber - 1)
}
milestone(buildNumber)

def buildResult = 'PENDING'
String description = 'test using nrel/openstudio:3.6.1'
String context = 'nrel/openstudio:3.6.1'

// GitHub Notification here. Until the GitHub plugin is fixed. See https://issues.jenkins-ci.org/browse/JENKINS-54249'
// It sucks that you don't have a way to mark a status as "Skipped", but if we defer the creation of the status after Skip CI is checked, then you won't get any status on the PR
// letting you know that the build is actually pending and with a link to go check on Jenkins. And that can take several hours for the windows instance.
githubNotify description: "${description}", context: "${context}", status: "${buildResult}", credentialsId: 'ci-commercialbuildings-test'

parallel(
    'ruby-tests': {
        node('nrel_docker_vcpu80') {
            String linux_base = '/srv/data/jenkins/git'

            dir("${linux_base}/${env.JOB_NAME}/${env.BUILD_NUMBER}") {
                // clear dir if previous contents
                deleteDir()

                checkout scm

                echo 'running in docker image nrel/openstudio:3.6.1'
                docker.image('nrel/openstudio:3.6.1').inside('-e "JENKINS_HOME=true" -u root -e "LANG=en_US.UTF-8"') {
                    sh('locale-gen en_US.UTF-8')
                    stage('show environment') {
                        try {
                            sh('ruby -v')
                            sh('echo "$"')
                            sh('openstudio openstudio_version')
                        } catch (Exception e) {
                            e.printStackTrace()
                            buildResult = 'FAILURE'
                            description = "${description} - CI Setup Failures"
                        }
                    }

                    stage('install dependencies') {
                        try {
                            sh("gem install bundler -v '2.1.4'")
                            sh('pwd')
                            sh '''
                                export GEM_PATH="/var/oscli/gems/ruby/2.7.0"
                                unset BUNDLE_WITHOUT
                                bundle config set git.allow_insecure true
                                bundle config set path /var/oscli/gems
                            '''
                            sh('bundle install --gemfile ./resources/Gemfile')
                        } catch (Exception e) {
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
                        } catch (Exception e) {
                            e.printStackTrace()
                            buildResult = 'FAILURE'
                            description = "${description} - Test Failures"
                        } finally {
                            try {
                                sh('cd ..')
                                sh('pwd')
                                archiveArtifacts artifacts: 'test/reports2/*.xml', fingerprint: true
                                junit testResults: 'test/reports2/*.xml', skipPublishingChecks: true
                            } catch (Exception e) {
                                buildResult = 'FAILURE'
                                description = "${description} - Artifact Download Failures"
                                e.printStackTrace()
                            }
                        }
                    }

                    stage('run resources measure tests') {
                        try {
                            timeout(time: 600, unit: 'MINUTES') {
                                sh '''
                                    bundle config set without 'native_ext'
                                    cd ./resources/
                                    bundle exec rake unit_tests:resource_measure_tests
                                '''
                            }
                        } catch (Exception e) {
                            e.printStackTrace()
                            buildResult = 'FAILURE'
                            description = "${description} - Test Failures"
                        } finally {
                            try {
                                sh('cd ..')
                                sh('pwd')
                                archiveArtifacts artifacts: 'test/reports2/*.xml', fingerprint: true
                                junit testResults: 'test/reports2/*.xml', skipPublishingChecks: true
                            } catch (Exception e) {
                                buildResult = 'FAILURE'
                                description = "${description} - Artifact Download Failures"
                                e.printStackTrace()
                            }
                        }
                    }

                    // docker user is root so all file permissions need to be changed for Jenkins to cleanup
                    sh "chmod -R 777 ${linux_base}/${env.JOB_NAME}/${env.BUILD_NUMBER}"
                }
                // cleanup workspace
                deleteDir()

                // Notify GitHub of result
                if ((buildResult != 'FAILURE') && (buildResult != 'ERROR')) {
                    buildResult = 'SUCCESS'
                }
                githubNotify description: "${description}", context: "${context}", status: "${buildResult}", credentialsId: 'ci-commercialbuildings-test'
                currentBuild.result = "${buildResult}"
            }
        }
    },
    'python-unittest': {
        node("openstudio-ubuntu-1804-nrel") {
            String linux_base = "/srv/jenkins/openstudio/git/";
            dir("${linux_base}/${env.JOB_NAME}/${env.BUILD_NUMBER}-unittest") {
                deleteDir()

                checkout scm
                // Need to mount the conan directory for data cache
                docker.image('nrel/openstudio-cmake-tools:ubuntu-20.04').inside('-u root -e "LANG=en_US.UTF-8"') {

                    stage("python unittest") {
                        try {
                            sh"""
                            cd ./postprocessing
                            pip3 install -e .[dev]
                            pytest . --junitxml=../test/report.xml
                            """
                        } catch (Exception e) {
                            e.printStackTrace()
                            buildResult = 'FAILURE'
                            description = "${description} - Test Failures"
                        } finally {
                            try {
                                archiveArtifacts artifacts: 'test/*.xml', fingerprint: true
                                junit testResults: 'test/*.xml', skipPublishingChecks: true
                            } catch (Exception e) {
                                buildResult = 'FAILURE'
                                description = "${description} - Artifact Download Failures"
                                e.printStackTrace()
                            }
                        }
                        // not ideal but we are in relative dir inside the container. The linux_base is mounted here so this is what we are
                        // deleting
                        sh "chmod -R 777 ${linux_base}/${env.JOB_NAME}/${env.BUILD_NUMBER}-unittest"
                    }
                    deleteDir();
                }
            }
        }
    },
    'python-intergrated-test': {
        node("openstudio-ubuntu-1804-nrel") {
            String linux_base = "/srv/jenkins/openstudio/git/";
            dir("${linux_base}/${env.JOB_NAME}/${env.BUILD_NUMBER}") {
                deleteDir()

                checkout scm
                // Need to mount the conan directory for data cache
                docker.image('kuangwenyi/buildstock_tools:23-10').inside('-u root -e "LANG=en_US.UTF-8"') {
                    stage("comstock intergrated test") {
                        sh"""
                        buildstock_local ymls/bsb-integration-test-baseline.yml
                        """
                        // not ideal but we are in relative dir inside the container. The linux_base is mounted here so this is what we are
                        // deleting
                        sh "chmod -R 777 ${linux_base}/${env.JOB_NAME}/${env.BUILD_NUMBER}"

                    }
                    deleteDir();
                }
            }
        }
    }
)
