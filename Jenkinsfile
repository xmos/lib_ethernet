// This file relates to internal XMOS infrastructure and should be ignored by external users

@Library('xmos_jenkins_shared_library@v0.36.0') _

getApproval()

pipeline {
  agent {
    label 'documentation&&linux&&x86_64'
  }
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
    choice(name: 'TEST_TYPE', choices: ['fixed_seed', 'random_seed'],
          description: 'Run tests with either a fixed seed or a randomly generated seed')
  }
  environment {
    REPO = 'lib_ethernet'
    PIP_VERSION = "24.0"
    SEED = "12345"
  }
  stages {
    stage('Build + Documentation') {
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
            sh "git clone git@github.com:xmos/test_support"
            sh "git -C test_support checkout e62b73a1260069c188a7d8fb0d91e1ef80a3c4e1"
            dir("${REPO}") {
              withVenv {
                sh "pip install -e ../test_support"
                withTools(params.TOOLS_VERSION) {
                  dir("tests") {
                    unstash 'test_bin'
                    script {
                    // Build all apps in the examples directory
                      if(params.TEST_TYPE == 'fixed_seed')
                      {
                        echo "Running tests with fixed seed ${env.SEED}"
                        sh "pytest -v -n auto --junitxml=pytest_result.xml --seed ${env.SEED} -k 'not hw' "
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
            cleanup {
            xcoreCleanSandbox()
            } // cleanup
          } // post
        } // stage('Simulator tests')
        stage('HW tests') {
          agent {
            label 'ethernet_testing'
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
            sh "git clone git@github.com:xmos/test_support"
            sh "git -C test_support checkout e62b73a1260069c188a7d8fb0d91e1ef80a3c4e1"

            sh "git clone git@github.com:xmos/hardware_test_tools"
            sh "git -C hardware_test_tools checkout 2f9919c956f0083cdcecb765b47129d846948ed4"

            dir("${REPO}") {
              withVenv {
                sh "pip install -e ../test_support"
                sh "pip install -e ../hardware_test_tools"
                sh "pip install cmake"
                withTools(params.TOOLS_VERSION) {
                  dir("tests") {
                    // Build all apps in the examples directory
                    unstash 'test_bin'
                    sh "pytest -v -n auto --junitxml=pytest_result.xml --adapter-id JnD5pZ3Q --eth-intf eno1 --test-duration 12 -k 'hw' "
                    junit "pytest_result.xml"
                  } // dir("tests")
                } // withTools
              } // withVenv
            } // dir("${REPO}")
          } // steps
          post {
            cleanup {
              xcoreCleanSandbox()
            } // cleanup
          } // post
        } // stage('HW tests')
      } // parallel
    } // stage('Tests')
  } // stages
} // pipeline
