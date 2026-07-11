def runCapture(String cmd) {
  return sh(script: cmd, returnStdout: true).trim()
}

def splitCsv(String value) {
  value?.split(',')?.collect { it.trim() }?.findAll { it } ?: []
}

def computeChangedFiles() {
  def cmd

  if (env.CHANGE_TARGET) {
    cmd = "git diff --name-only origin/${env.CHANGE_TARGET}...HEAD"
  } else if (env.GIT_PREVIOUS_SUCCESSFUL_COMMIT && env.GIT_COMMIT) {
    cmd = "git diff --name-only ${env.GIT_PREVIOUS_SUCCESSFUL_COMMIT}..${env.GIT_COMMIT}"
  } else if (env.GIT_PREVIOUS_COMMIT && env.GIT_COMMIT) {
    cmd = "git diff --name-only ${env.GIT_PREVIOUS_COMMIT}..${env.GIT_COMMIT}"
  } else {
    cmd = 'git show --name-only --pretty="" HEAD'
  }

  try {
    return splitCsv(runCapture(cmd).replace('\n', ','))
  } catch (err) {
    echo "Changed-file detection failed with '${cmd}'. Falling back to latest commit only."
    return splitCsv(runCapture('git -c color.ui=never show --name-only --pretty="" HEAD').replace('\n', ','))
  }
}

pipeline {
  agent any

  parameters {
    booleanParam(name: 'BUILD_ALL', defaultValue: false, description: 'Build all services')
    booleanParam(name: 'RUN_FEATURE_BRANCH_TESTS', defaultValue: false, description: 'Run Maven tests on non-main branches')
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
        script {
          if (env.CHANGE_TARGET) {
            sh "git fetch --no-tags origin ${env.CHANGE_TARGET}"
          }
          if (env.BRANCH_NAME) {
            sh '''
              if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
                git fetch --no-tags --deepen=50 origin "$BRANCH_NAME"
              fi
            '''
          }
        }
      }
    }

    stage('Detect Changes') {
      steps {
        script {
          def allMavenModules = splitCsv(env.MAVEN_MODULES.replace(' ', ','))
          def allDockerServices = splitCsv(env.DOCKER_SERVICES.replace(' ', ','))
          def changedFiles = computeChangedFiles()
            .collect { it.replace('\\', '/').replaceFirst(/^\.\//, '').trim() }
            .findAll { it }

          def rebuildAll = params.BUILD_ALL || changedFiles.any { f ->
            f == 'pom.xml' || f.startsWith('common-library/') || f.startsWith('checkstyle/')
          }

          def affectedMaven = rebuildAll ? allMavenModules : allMavenModules.findAll { module ->
            changedFiles.any { f -> f == module || f.startsWith("${module}/") }
          }

          def affectedDocker = rebuildAll ? allDockerServices : allDockerServices.findAll { service ->
            changedFiles.any { f -> f == service || f.startsWith("${service}/") }
          }

          env.AFFECTED_MODULES = affectedMaven.join(',')
          env.AFFECTED_DOCKER_MODULES = affectedDocker.join(',')
          env.IMAGE_TAG = runCapture('git rev-parse --short=8 HEAD')

          echo "Changed files:\n${changedFiles.join('\n')}"
          echo "Affected Maven modules: ${env.AFFECTED_MODULES ?: 'none'}"
          echo "Affected Docker services: ${env.AFFECTED_DOCKER_MODULES ?: 'none'}"
          echo "Image tag: ${env.IMAGE_TAG}"

          currentBuild.description = "${env.BRANCH_NAME ?: ''} | ${env.AFFECTED_DOCKER_MODULES ?: 'no service changes'}"
        }
      }
    }

    stage('Gitleaks Scan') {
      steps {
        script {
          int status = sh(
            script: '''
              if ! command -v gitleaks >/dev/null 2>&1; then
                if [ ! -x ./gitleaks ]; then
                  curl -ssfL https://github.com/gitleaks/gitleaks/releases/download/v8.18.2/gitleaks_8.18.2_linux_x64.tar.gz | tar -xz gitleaks
                  chmod +x ./gitleaks
                fi
                GITLEAKS_CMD=./gitleaks
              else
                GITLEAKS_CMD=gitleaks
              fi

              "$GITLEAKS_CMD" detect --source . --config gitleaks.toml --verbose --no-git
            ''',
            returnStatus: true
          )

          if (status != 0) {
            unstable('Gitleaks found issues')
          } else {
            echo 'No secrets detected'
          }
        }
      }
    }

    stage('Build') {
      when {
        expression { env.AFFECTED_MODULES?.trim() }
      }
      steps {
        sh "mvn ${env.MVN_ARGS} -pl ${env.AFFECTED_MODULES} -am -DskipTests clean package"
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
        sh """
          mvn ${env.MVN_ARGS} \
            -pl ${env.AFFECTED_MODULES} -am \
            verify \
            -ff \
            -DtrimStackTrace=true \
            -Dsurefire.printSummary=true \
            -Dfailsafe.printSummary=true
        """
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
        script {
          def dockerServices = splitCsv(env.AFFECTED_DOCKER_MODULES).findAll { service ->
            fileExists("${service}/Dockerfile")
          }

          if (!dockerServices) {
            echo 'No affected service has a Dockerfile. Skipping image push.'
            return
          }

          withCredentials([usernamePassword(
            credentialsId: env.DOCKERHUB_CREDENTIALS_ID,
            usernameVariable: 'DOCKERHUB_USERNAME',
            passwordVariable: 'DOCKERHUB_PASSWORD'
          )]) {
            sh '''
              set +x
              printf '%s' "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
            '''

            dockerServices.each { service ->
              withEnv(["SERVICE_NAME=${service}"]) {
                sh '''
                  push_image_with_retry() {
                    image="$1"
                    attempt=1
                    max_attempts=5

                    while [ "$attempt" -le "$max_attempts" ]; do
                      echo "Pushing ${image} (attempt ${attempt}/${max_attempts})"
                      if docker push "${image}"; then
                        return 0
                      fi

                      if [ "$attempt" -eq "$max_attempts" ]; then
                        echo "Failed to push ${image} after ${max_attempts} attempts"
                        return 1
                      fi

                      sleep_seconds=$((attempt * 20))
                      echo "Push failed for ${image}. Retrying in ${sleep_seconds}s..."
                      sleep "$sleep_seconds"
                      attempt=$((attempt + 1))
                    done
                  }

                  IMAGE="${DOCKERHUB_NAMESPACE}/yas-${SERVICE_NAME}:${IMAGE_TAG}"
                  if [ "${SERVICE_NAME}" = "backoffice" ]; then
                    IMAGE="${DOCKERHUB_NAMESPACE}/yas-backoffice:${IMAGE_TAG}"
                  fi
                  if [ "${SERVICE_NAME}" = "storefront" ]; then
                    IMAGE="${DOCKERHUB_NAMESPACE}/yas-storefront:${IMAGE_TAG}"
                  fi

                  echo "Building ${IMAGE}"
                  if [ "${SERVICE_NAME}" = "media" ]; then
                    rm -rf media/images
                    cp -a sampledata/images media/images
                  fi

                  docker build --pull -t "${IMAGE}" "${SERVICE_NAME}"
                  push_image_with_retry "${IMAGE}"

                  if [ "${BRANCH_NAME}" = "main" ]; then
                    MAIN_IMAGE="${IMAGE%:*}:main"
                    LATEST_IMAGE="${IMAGE%:*}:latest"
                    docker tag "${IMAGE}" "${MAIN_IMAGE}"
                    docker tag "${IMAGE}" "${LATEST_IMAGE}"
                    push_image_with_retry "${MAIN_IMAGE}"
                    push_image_with_retry "${LATEST_IMAGE}"
                  fi
                '''
              }
            }

            sh 'docker logout || true'
          }
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
    success {
      echo 'Pipeline SUCCESS'
    }
    unstable {
      echo 'Pipeline UNSTABLE'
    }
    failure {
      echo 'Pipeline FAILED'
    }
  }
}
