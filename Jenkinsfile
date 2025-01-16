// This file relates to internal XMOS infrastructure and should be ignored by external users

@Library('xmos_jenkins_shared_library@v0.34.0') _

getApproval()

pipeline {
  agent {
    label 'documentation&&linux&&x86_64'
  }
  options {
    buildDiscarder(xmosDiscardBuildSettings())
    skipDefaultCheckout()
  }
  parameters {
    string(
      name: 'TOOLS_VERSION',
      defaultValue: '15.3.0',
      description: 'The XTC tools version'
    )
    string(
      name: 'XMOSDOC_VERSION',
      defaultValue: 'v6.1.3',
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
    PYTHON_VERSION = "3.12.1"
    SEED = "12345"
  }
  stages {
    stage('Checkout') {
      steps {
        println "Stage running on: ${env.NODE_NAME}"
        dir("${REPO}") {
          checkout scm
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
              sh "cmake -B build -G\"Unix Makefiles\" -DDEPS_CLONE_SHALLOW=TRUE"
              sh "xmake -j 32 -C build"
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

    stage('Simulator tests') {
      steps {
        sh "git clone git@github.com:xmos/test_support"
        sh "git -C test_support checkout e62b73a1260069c188a7d8fb0d91e1ef80a3c4e1"
        dir("${REPO}") {
          withVenv {
            sh "pip install -e ../test_support"
            withTools(params.TOOLS_VERSION) {
              dir("tests") {
                script {
                // Build all apps in the examples directory
                  sh "cmake -B build -G\"Unix Makefiles\" -DDEPS_CLONE_SHALLOW=TRUE"
                  sh "xmake -j 32 -C build"
                  if(params.TEST_TYPE == 'fixed_seed')
                  {
                    echo "Running tests with fixed seed ${env.SEED}"
                    sh "pytest -v -n auto --junitxml=pytest_result.xml --seed ${env.SEED}"
                  }
                  else
                  {
                    echo "Running tests with random seed"
                    sh "pytest -v -n auto --junitxml=pytest_result.xml"
                  }
                  junit "pytest_result.xml"
                } // script
              } // dir("tests")
            } // withTools
          } // withVenv
        } // dir("${REPO}")
      } // steps
    } // stage('Simulator tests')

  } // stages

  post {
    cleanup {
      xcoreCleanSandbox()
    } // cleanup
  } // post
} // pipeline
