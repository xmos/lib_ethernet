@Library('xmos_jenkins_shared_library@v0.16.2') _

getApproval()

pipeline {
  agent none
  stages {
    stage('Standard builds and tests') {
      agent {
        label 'x86_64&&brew&&macOS'
      }
      environment {
        REPO = 'lib_ethernet'
        VIEW = getViewName(REPO)
      }
      options {
        skipDefaultCheckout()
      }
      stages {
        stage('Get view') {
          steps {
            xcorePrepareSandbox("${VIEW}", "${REPO}")
          }
        }
        stage('Library checks') {
          steps {
             xcoreLibraryChecks("${REPO}")
          }
        }
        stage('xCORE App XS2 builds') {
          steps {
            forAllMatch("${REPO}/examples", "app_*/") { path ->
              runXmake(path)
            }
            forAllMatch("${REPO}/examples", "AN*/") { path ->
              runXmake(path)
            }
          }
        }
        stage('Doc builds') {
          steps {
            runXdoc("${REPO}/${REPO}/doc")
            forAllMatch("${REPO}/examples", "AN*/") { path ->
              runXdoc("${path}/doc")
            }
          }
        }
        stage('Tests XS1 and XS2') {
          steps {
            runXmostest("${REPO}", 'tests')
          }
        }
      }
      post {
        cleanup {
          xcoreCleanSandbox()
        }
      }
    }
  }
  post {
    success {
      node("linux") {
        updateViewfiles()
        xcoreCleanSandbox()
      }
    }
  }
}
