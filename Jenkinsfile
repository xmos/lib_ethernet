// This file relates to internal XMOS infrastructure and should be ignored by external users

@Library('xmos_jenkins_shared_library@v0.36.0') _

def clone_test_deps() {
  dir("${WORKSPACE}") {
    sh "git clone git@github.com:xmos/test_support"
    sh "git -C test_support checkout e62b73a1260069c188a7d8fb0d91e1ef80a3c4e1"

    sh "git clone git@github.com:xmos/hardware_test_tools"
    sh "git -C hardware_test_tools checkout 2f9919c956f0083cdcecb765b47129d846948ed4"

    sh "git clone git@github0.xmos.com:xmos-int/xtagctl"
    sh "git -C xtagctl checkout v2.0.0"
  }
}

getApproval()

pipeline {
  agent none
  options {
    buildDiscarder(xmosDiscardBuildSettings())
    skipDefaultCheckout()
    timestamps()
  }
  parameters {
    string(
      name: 'TOOLS_VERSION',
      defaultValue: '15.3.0',
      description: 'The XTC tools version'
    )
    string(
      name: 'XMOSDOC_VERSION',
      defaultValue: 'v6.2.0',
      description: 'The xmosdoc version'
    )
    string(
        name: 'INFR_APPS_VERSION',
        defaultValue: 'v2.0.1',
        description: 'The infr_apps version'
    )
    choice(name: 'TEST_TYPE', choices: ['smoke', 'nightly'],
          description: 'Run tests with either a fixed seed or a randomly generated seed')
  }
  environment {
    REPO = 'lib_ethernet'
    PIP_VERSION = "24.0"
    SEED = "12345"
  }
  stages {
    stage('Build + Documentation') {
      agent {
        label 'documentation&&linux&&x86_64'
      }
      stages {
        stage('Checkout') {
          environment {
            PYTHON_VERSION = "3.12.1"
          }
          steps {
            println "Stage running on: ${env.NODE_NAME}"
            dir("${REPO}") {
              checkoutScmShallow()
              createVenv()
              installPipfile(false)
            }
          }
        }  // Get sandbox

        stage('Build examples') {
          steps {
            withTools(params.TOOLS_VERSION) {
              dir("${REPO}/examples") {
                script {
                  echo "Test Stage: SEED is ${env.SEED}"
                  // Build all apps in the examples directory
                  xcoreBuild()
                } // script
              } // dir
            } //withTools
          } // steps
        }  // Build examples

        stage('Library checks') {
          steps {
            warnError("lib checks") {
              runLibraryChecks("${WORKSPACE}/${REPO}", "${params.INFR_APPS_VERSION}")
            }
          }
        }

        stage('Documentation') {
          steps {
            dir("${REPO}") {
              warnError("Docs") {
                buildDocs()
                dir("examples/app_rmii_100Mbit_icmp") {
                  buildDocs()
                }
              }
            }
          }
        }
        stage('Build tests') {
          steps {
            dir("${REPO}") {
              withVenv {
                withTools(params.TOOLS_VERSION) {
                  dir("tests") {
                    xcoreBuild()
                    stash includes: '**/*.xe', name: 'test_bin', useDefaultExcludes: false
                  }
                } // withTools(params.TOOLS_VERSION)
              } // withVenv
            } // dir("${REPO}")
          } // steps
        } // stage('Build tests')
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
          environment {
              PYTHON_VERSION = "3.12.1"
            }
          agent {
            label 'linux && x86_64'
          }
          steps {
            dir("${REPO}") {
              checkoutScmShallow()
              createVenv()
              installPipfile(false)
            }
            clone_test_deps()
            dir("${REPO}") {
              withVenv {
                sh "pip install -e ../test_support"
                sh "pip install -e ../hardware_test_tools"
                withTools(params.TOOLS_VERSION) {
                  dir("tests") {
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
                      junit "pytest_result.xml"
                    } // script
                  } // dir("tests")
                } // withTools
              } // withVenv
            } // dir("${REPO}")
          } // steps
          post {
            always {
              archiveArtifacts artifacts: "${REPO}/tests/ifg_*.txt", fingerprint: true, allowEmptyArchive: true
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
          environment {
            PYTHON_VERSION = "3.12.3"
          }
          steps {
            dir("${REPO}") {
              checkoutScmShallow()
              createVenv()
              installPipfile(false)
            }

            clone_test_deps()

            dir("${REPO}") {
              withVenv {
                sh "pip install -e ../test_support"
                sh "pip install -e ../hardware_test_tools"
                sh "pip install -e ../xtagctl"
                withTools(params.TOOLS_VERSION) {
                  dir("tests") {
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
                    junit "pytest_result.xml"
                  } // dir("tests")
                } // withTools
              } // withVenv
            } // dir("${REPO}")
          } // steps
          post {
            always {
              archiveArtifacts artifacts: "${REPO}/tests/*_fail.pcapng", fingerprint: true, allowEmptyArchive: true
              archiveArtifacts artifacts: "${REPO}/tests/ifg_sweep_*.txt", fingerprint: true, allowEmptyArchive: true
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
          environment {
            PYTHON_VERSION = "3.12.3"
          }
          steps {
            dir("${REPO}") {
              checkoutScmShallow()
              createVenv()
              installPipfile(false)
            }

            clone_test_deps()

            dir("${REPO}") {
              withVenv {
                sh "pip install -e ../test_support"
                sh "pip install -e ../hardware_test_tools"
                sh "pip install -e ../xtagctl"
                withTools(params.TOOLS_VERSION) {
                  dir("tests") {
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
                    junit "pytest_result.xml"
                  } // dir("tests")
                } // withTools
              } // withVenv
            } // dir("${REPO}")
          } // steps
          post {
            always {
              archiveArtifacts artifacts: "${REPO}/tests/*_fail.pcapng", fingerprint: true, allowEmptyArchive: true
              archiveArtifacts artifacts: "${REPO}/tests/ifg_sweep_*.txt", fingerprint: true, allowEmptyArchive: true
            }
            cleanup {
              xcoreCleanSandbox()
            } // cleanup
          } // post
        } // stage('HW tests')
      } // parallel
    } // stage('Tests')
  } // stages
} // pipeline