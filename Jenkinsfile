pipeline {
    agent any

    environment {
        IMAGE_NAME = 'sentiment-ai'
        REGISTRY = 'ghcr.io/andmadeleine'
        IMAGE_TAG = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                echo "Branche : ${env.BRANCH_NAME}"
                echo "Commit : ${env.GIT_COMMIT}"
                sh 'git log --oneline -5'
            }
        }

        stage('Lint') {
            steps {
                sh '''
                docker run --rm \
                --volumes-from jenkins \
                -w $WORKSPACE \
                python:3.12-slim \
                sh -c "pip install flake8 -q && flake8 src/ --max-line-length=100"
                '''
            }
        }

        stage('Terraform Validate') {
            steps {
                sh '''
                docker run --rm \
                --volumes-from jenkins \
                -w $WORKSPACE/infra \
                hashicorp/terraform:latest \
                init -backend=false -input=false

                docker run --rm \
                --volumes-from jenkins \
                -w $WORKSPACE/infra \
                hashicorp/terraform:latest \
                fmt -check

                docker run --rm \
                --volumes-from jenkins \
                -w $WORKSPACE/infra \
                hashicorp/terraform:latest \
                validate
                '''
            }
        }

        stage('Build & Test') {
            steps {
                sh '''
                docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .

                docker rm -f test-runner 2>/dev/null || true

                set +e
                docker run \
                -e CI=true \
                --name test-runner \
                ${IMAGE_NAME}:${IMAGE_TAG} \
               pytest tests/ -v \
                --cov=src \
                --cov-report=xml \
                --cov-report=term-missing \
                --cov-fail-under=70

                TEST_EXIT_CODE=$?
                set -e

                docker cp test-runner:/app/coverage.xml ./coverage.xml
                docker rm -f test-runner 2>/dev/null || true

                exit $TEST_EXIT_CODE
                '''
            }
        }

        stage('SonarQube Analysis') {
            environment {
                SONARQUBE_TOKEN = credentials('sonar-token')
            }

            steps {
                withSonarQubeEnv('sonarqube') {
                    sh '''
                    docker run --rm \
                    --network cicd-network \
                    --volumes-from jenkins \
                    -w "$WORKSPACE" \
                    -e SONAR_HOST_URL=http://sonarqube:9000 \
                    -e SONAR_TOKEN="$SONARQUBE_TOKEN" \
                    sonarsource/sonar-scanner-cli:latest \
                    sonar-scanner \
                    -Dsonar.projectKey=sentiment-ai \
                    -Dsonar.projectName=SentimentAI \
                    -Dsonar.projectBaseDir="$WORKSPACE" \
                    -Dsonar.sources=src \
                    -Dsonar.python.version=3.11 \
                    -Dsonar.python.coverage.reportPaths=coverage.xml \
                    -Dsonar.sourceEncoding=UTF-8 \
                    -Dsonar.scanner.metadataFilePath="$WORKSPACE/report-task.txt"
                    -Dsonar.sources=src \
                    -Dsonar.tests=tests \
                    -Dsonar.python.coverage.reportPaths=coverage.xml \
                    -Dsonar.projectBaseDir=$WORKSPACE
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Trivy Scan') {
            steps {
                sh '''
                docker run --rm \
                -v /var/run/docker.sock:/var/run/docker.sock \
                aquasec/trivy:latest image \
                --severity HIGH,CRITICAL \
                --exit-code 0 \
                ${IMAGE_NAME}:${IMAGE_TAG}
                '''
            }
        }

        stage('Push') {
            when {
                expression {
                    env.GIT_BRANCH == 'origin/main' || env.BRANCH_NAME == 'main'
                }
            }

            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'github-token',
                    usernameVariable: 'REGISTRY_USER',
                    passwordVariable: 'REGISTRY_PASS'
                )]) {
                    sh '''
                    echo $REGISTRY_PASS | docker login ghcr.io -u $REGISTRY_USER --password-stdin
                    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                    docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:latest
                    docker push ${REGISTRY}/${IMAGE_NAME}:latest
                    '''
                }
            }
        }

        stage('Terraform Apply') {
            when {
                expression {
                    env.GIT_BRANCH == 'origin/main' || env.BRANCH_NAME == 'main'
                }
            }

            steps {
                sh '''
                docker rm -f sentiment-staging 2>/dev/null || true

                docker run --rm \
                --volumes-from jenkins \
                -w $WORKSPACE/infra \
                hashicorp/terraform:latest \
                init -input=false

                docker run --rm \
                --volumes-from jenkins \
                -w $WORKSPACE/infra \
                hashicorp/terraform:latest \
                apply -auto-approve \
                -var="image_tag=${IMAGE_TAG}"
                '''
            }
        }

stage('Deploy Staging') {
    when {
        expression {
            env.GIT_BRANCH == 'origin/main' || env.BRANCH_NAME == 'main'
        }
    }

    steps {
        sh '''
        docker run --rm \
          --network cicd-network \
          curlimages/curl:latest \
          curl -f http://sentiment-staging:8000/health
        '''
    }
}


        stage('Smoke Test') {
            when {
                expression {
                    env.GIT_BRANCH == 'origin/main' || env.BRANCH_NAME == 'main'
                }
            }

            steps {
                sh '''
                echo "Attente demarrage (10s)..."
                sleep 10

                docker run --rm \
                  --network cicd-network \
                  curlimages/curl:latest \
                  curl -f http://sentiment-staging:8000/health

                echo "/health OK"

                docker run --rm \
                  --network cicd-network \
                  curlimages/curl:latest \
                  curl -s http://sentiment-staging:8000/metrics | grep -q sentiment_predictions_total

                echo "/metrics OK -- metriques SentimentAI presentes"

                sleep 20

                docker run --rm \
                  --network cicd-network \
                  curlimages/curl:latest \
                  curl -s "http://prometheus:9090/api/v1/query?query=up{job='sentiment-ai'}" | grep -q '"value":.*"1"'

                echo "Prometheus scrape sentiment-ai : UP"

                docker run --rm \
                  --network cicd-network \
                  curlimages/curl:latest \
                  curl -f http://grafana:3000/api/health

                echo "Grafana OK"
                '''
            }
        }
    }

    post {
        always {
            sh 'docker compose down -v 2>/dev/null || true'
        }

        success {
            echo "Pipeline reussi. Image : ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        }

        failure {
            echo "Pipeline echoue. Consultez les logs."
        }
    }
}