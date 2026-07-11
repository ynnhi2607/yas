pipeline {
  agent any

  parameters {
    booleanParam(name: 'BUILD_ALL', defaultValue: false, description: 'Build all Maven and Docker services')
    booleanParam(name: 'RUN_FEATURE_BRANCH_TESTS', defaultValue: false, description: 'Run full tests on non-main branches')
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    MVN_ARGS = '-B -ntp'
    DOCKER_BUILDKIT = '0'
    TESTCONTAINERS_RYUK_DISABLED = 'true'
    DOCKERHUB_NAMESPACE = 'ynnhi2607'
    DOCKERHUB_CREDENTIALS_ID = 'dockerhub'
    MAVEN_MODULES = 'backoffice-bff cart customer inventory location media order payment product search storefront-bff tax sampledata'
    DOCKER_SERVICES = 'backoffice backoffice-bff cart customer inventory location media order payment product search tax sampledata storefront storefront-bff'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          if [ -n "${CHANGE_TARGET:-}" ]; then
            git fetch --no-tags origin "$CHANGE_TARGET"
          fi
          if [ -n "${BRANCH_NAME:-}" ] && [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
            git fetch --no-tags --deepen=50 origin "$BRANCH_NAME"
          fi
        '''
      }
    }

    stage('Detect Changes') {
      steps {
        sh 'bash jenkins/scripts/detect-changes.sh'
        script {
          readFile('.jenkins-ci-env').split(/\r?\n/).findAll { it.trim() }.each { line ->
            def parts = line.split('=', 2)
            env[parts[0]] = parts.length > 1 ? parts[1] : ''
          }
          currentBuild.description = "${env.BRANCH_NAME ?: ''} | ${env.AFFECTED_DOCKER_MODULES ?: 'no service changes'}"
        }
      }
    }

    stage('Gitleaks Scan') {
      steps {
        catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
          sh 'bash jenkins/scripts/gitleaks-scan.sh'
        }
      }
    }

    stage('Build') {
      when {
        expression { env.AFFECTED_MODULES?.trim() }
      }
      steps {
        sh 'mvn ${MVN_ARGS} -pl "${AFFECTED_MODULES}" -am -DskipTests clean package'
      }
    }

    stage('Unit & Integration Tests') {
      when {
        expression {
          env.AFFECTED_MODULES?.trim() &&
          (env.BRANCH_NAME == 'main' || params.RUN_FEATURE_BRANCH_TESTS)
        }
      }
      options {
        timeout(time: 30, unit: 'MINUTES')
      }
      steps {
        sh '''
          mvn ${MVN_ARGS} \
            -pl "${AFFECTED_MODULES}" -am \
            verify \
            -ff \
            -DtrimStackTrace=true \
            -Dsurefire.printSummary=true \
            -Dfailsafe.printSummary=true
        '''
      }
      post {
        always {
          junit allowEmptyResults: true,
            testResults: '**/target/surefire-reports/*.xml, **/target/failsafe-reports/*.xml'
        }
      }
    }

    stage('Build and Push Docker Images') {
      when {
        expression {
          env.AFFECTED_DOCKER_MODULES?.trim() &&
          !env.CHANGE_ID &&
          !env.TAG_NAME
        }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId: env.DOCKERHUB_CREDENTIALS_ID,
          usernameVariable: 'DOCKERHUB_USERNAME',
          passwordVariable: 'DOCKERHUB_PASSWORD'
        )]) {
          sh 'bash jenkins/scripts/build-push-images.sh'
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts allowEmptyArchive: true,
        artifacts: '**/target/*.jar, **/target/surefire-reports/*.xml, **/target/failsafe-reports/*.xml'
      echo 'Pipeline finished.'
    }
  }
}
