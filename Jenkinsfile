// This file relates to internal XMOS infrastructure and should be ignored by external users

@Library('xmos_jenkins_shared_library@v0.42.0') _

getApproval()

pipeline {

  agent none

  options {
    buildDiscarder(xmosDiscardBuildSettings(onlyArtifacts = false))
    skipDefaultCheckout()
    timestamps()
  }
  parameters {
    string(
      name: 'TOOLS_VERSION',
      defaultValue: '15.3.1',
      description: 'The XTC tools version'
    )
    string(
      name: 'XMOSDOC_VERSION',
      defaultValue: 'v7.4.0',
      description: 'The xmosdoc version'
    )
    string(
        name: 'INFR_APPS_VERSION',
        defaultValue: 'v3.1.1',
        description: 'The infr_apps version'
    )
    choice(name: 'TEST_TYPE', choices: ['smoke', 'nightly'],
          description: 'Run tests with either a fixed seed or a randomly generated seed')
  }
  environment {
    SEED = "12345"
  }

  stages {
    stage('Build + Documentation') {
      agent {
        label 'documentation && linux && x86_64'
      }

      stages {
        stage('Checkout') {
          steps {
            println "Stage running on: ${env.NODE_NAME}"

            script {
                def (server, user, repo) = extractFromScmUrl()
                env.REPO_NAME = repo
            }

            dir(REPO_NAME) {
              checkoutScmShallow()
            }
          }
        }  // Get sandbox

        stage('Build examples') {
          steps {
            dir("${REPO_NAME}/examples") {
              println "Test Stage: SEED is ${env.SEED}"
              // Build all apps in the examples directory
              xcoreBuild()
            } // dir
          } // steps
        }  // Build examples

        stage('Library checks') {
          steps {
            warnError("lib checks") {
              runRepoChecks("${WORKSPACE}/${REPO_NAME}")
            }
          }
        }

        stage('Documentation') {
          steps {
            dir(REPO_NAME) {
              buildDocs()
            }
          }
        }

        stage('Build tests') {
          steps {
            dir("${REPO_NAME}/tests") {
              createVenv(reqFile: "requirements.txt")
              withVenv {
                  xcoreBuild()
                  stash includes: '**/*.xe', name: 'test_bin', useDefaultExcludes: false
              } // withVenv
            } // dir("${REPO_NAME}/tests")
          } // steps
        } // stage('Build tests')

        stage("Archive Lib") {
          steps {
            archiveSandbox(REPO_NAME)
          }
        } //stage("Archive Lib")
      } // stages

      post {
        cleanup {
          xcoreCleanSandbox()
        } // cleanup
      } // post
    } // stage('Build + Documentation')

    stage('Tests') {
      parallel {

        stage('Simulator tests') {
          agent {
            label 'linux && x86_64'
          }
          steps {
            dir(REPO_NAME) {
              checkoutScmShallow()
            }
            
            dir("${REPO_NAME}/tests") {
              createVenv(reqFile: "requirements.txt")
              withVenv {
                withTools(params.TOOLS_VERSION) {
                  unstash 'test_bin'
                  script {
                  // Build all apps in the examples directory
                    if(params.TEST_TYPE == 'smoke')
                    {
                      echo "Running tests with fixed seed ${env.SEED}"
                      sh "pytest -v -n auto --junitxml=pytest_result.xml --seed ${env.SEED} -k 'not hw and not tx_ifg' "
                    }
                    else
                    {
                      echo "Running tests with random seed"
                      sh "pytest -v -n auto --junitxml=pytest_result.xml -k 'not hw' "
                    }
                  } // script
                } // withTools
              } // withVenv
            } // dir(REPO_NAME)
          } // steps
          post {
            always {
              junit "${REPO_NAME}/tests/pytest_result.xml"
              archiveArtifacts artifacts: "${REPO_NAME}/tests/ifg_*.txt", fingerprint: true, allowEmptyArchive: true
            }
            cleanup {
              xcoreCleanSandbox()
            } // cleanup
          } // post
        } // stage('Simulator tests')

        stage('HW tests - PHY0') {
          agent {
            label 'sw-hw-eth-ubu0'
          }
          steps {
            dir(REPO_NAME) {
              checkoutScmShallow()
            }
            dir("${REPO_NAME}/tests") {
              createVenv(reqFile: "requirements.txt")
              withVenv {
                withTools(params.TOOLS_VERSION) {
                  // Build all apps in the examples directory
                  unstash 'test_bin'
                  script {
                      // Set environment variable based on condition
                      def hwTestDuration = (params.TEST_TYPE == 'smoke') ? "20" : "60"
                      // Use withEnv to pass the variable to the shell
                      withEnv(["HW_TEST_DURATION=${hwTestDuration}"]) {
                        withXTAG(["xk-eth-xu316-dual-100m"]) { xtagIds ->
                          sh "pytest -v --junitxml=pytest_result.xml --adapter-id ${xtagIds[0]} --eth-intf eno1 --test-duration ${env.HW_TEST_DURATION} --phy phy0 -k 'hw' --timeout=600 --session-timeout=3600"
                        } // withXTAG
                      } // withEnv(["HW_TEST_DURATION=${hwTestDuration}"])
                  } // script
                } // withTools
              } // withVenv
            } // dir(REPO_NAME)
          } // steps
          post {
            always {
              junit "${REPO_NAME}/tests/pytest_result.xml"
              archiveArtifacts artifacts: "${REPO_NAME}/tests/*_fail.pcapng", fingerprint: true, allowEmptyArchive: true
              archiveArtifacts artifacts: "${REPO_NAME}/tests/ifg_sweep_*.txt", fingerprint: true, allowEmptyArchive: true
            }
            cleanup {
              xcoreCleanSandbox()
            } // cleanup
          } // post
        } // stage('HW tests - PHY0')

        stage('HW tests - PHY1') {
          agent {
            label 'sw-hw-eth-ubu1'
          }
          steps {
            dir(REPO_NAME) {
              checkoutScmShallow()
            }
            
            dir("${REPO_NAME}/tests") {
              createVenv(reqFile: "requirements.txt")
              withVenv {
                withTools(params.TOOLS_VERSION) {
                  // Build all apps in the examples directory
                  unstash 'test_bin'
                  script {
                      // Set environment variable based on condition
                      def hwTestDuration = (params.TEST_TYPE == 'smoke') ? "20" : "60"
                      // Use withEnv to pass the variable to the shell
                      withEnv(["HW_TEST_DURATION=${hwTestDuration}"]) {
                        withXTAG(["xk-eth-xu316-dual-100m"]) { xtagIds ->
                          sh "pytest -v --junitxml=pytest_result.xml --adapter-id ${xtagIds[0]} --eth-intf enp110s0 --test-duration ${env.HW_TEST_DURATION} --phy phy1 -k 'hw' --timeout=600 --session-timeout=3600"
                        } // withXTAG
                      } // withEnv(["HW_TEST_DURATION=${hwTestDuration}"])
                  } // script
                } // withTools
              } // withVenv
            } // dir(REPO_NAME)
          } // steps
          post {
            always {
              junit "${REPO_NAME}/tests/pytest_result.xml"
              archiveArtifacts artifacts: "${REPO_NAME}/tests/*_fail.pcapng", fingerprint: true, allowEmptyArchive: true
              archiveArtifacts artifacts: "${REPO_NAME}/tests/ifg_sweep_*.txt", fingerprint: true, allowEmptyArchive: true
            }
            cleanup {
              xcoreCleanSandbox()
            } // cleanup
          } // post
        } // stage('HW tests')
      } // parallel
    } // stage('Tests')
    
    stage('🚀 Release') {
      when {
        expression { triggerRelease.isReleasable() }
      }

      steps {
        triggerRelease()
      }
    }
  } // stages
} // pipeline