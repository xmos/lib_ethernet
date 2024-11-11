@Library('xmos_jenkins_shared_library@v0.32.0') _

getApproval()

pipeline {
  agent none
  stages {
    stage('Standard builds and tests') {
      agent {
        label 'x86_64&&macOS'
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

            // Archive all the generated .pdf docs
            archiveArtifacts artifacts: "${REPO}/**/pdf/*.pdf", fingerprint: true, allowEmptyArchive: true
          }
        }
        stage('Tests XS1 and XS2') {
          steps {
            runXmostest("${REPO}", 'tests')
            archiveArtifacts artifacts: "${REPO}/tests/**/*.xe", fingerprint: true, allowEmptyArchive: true
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
