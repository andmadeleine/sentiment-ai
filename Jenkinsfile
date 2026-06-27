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
                --cov-report=xml:/tmp/coverage.xml \
                --cov-report=term-missing \
                --cov-fail-under=70

                TEST_EXIT_CODE=$?
                set -e

                docker cp test-runner:/tmp/coverage.xml ./coverage.xml 2>/dev/null || true
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

stage('Terraform Init') {
    steps {
        dir('infra') {
            sh '''
            docker run --rm \
              --volumes-from jenkins \
              -w $WORKSPACE/infra \
              hashicorp/terraform:latest \
              init
            '''
        }
    }
}

stage('Terraform Plan') {
    steps {
        dir('infra') {
            sh '''
            docker run --rm \
              --volumes-from jenkins \
              -w $WORKSPACE/infra \
              hashicorp/terraform:latest \
              plan -out=tfplan
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
        dir('infra') {
            sh '''
            docker run --rm \
              --volumes-from jenkins \
              -w $WORKSPACE/infra \
              hashicorp/terraform:latest \
              apply -auto-approve tfplan
            '''
        }
    }
}


        stage('Trivy Scan') {
            steps {
        sh """
        docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        aquasec/trivy:latest image \
        --severity HIGH,CRITICAL \
        --exit-code 0 \
        ${IMAGE_NAME}:${IMAGE_TAG}
        """
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
                    sh """
                    echo \$REGISTRY_PASS | docker login ghcr.io -u \$REGISTRY_USER --password-stdin
                    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                    docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:latest
                    docker push ${REGISTRY}/${IMAGE_NAME}:latest
                    """
                }
            }
        }
    
stage('Deploy Staging') {
    when {
        expression {
            env.GIT_BRANCH == 'origin/main' || env.BRANCH_NAME == 'main'
        }
    }

    steps {
        echo "Deploiement de ${IMAGE_NAME}:${IMAGE_TAG} en staging"

        sh '''
        docker rm -f sentiment-staging 2>/dev/null || true

        docker run -d \
          --name sentiment-staging \
          --network cicd-network \
          -p 8001:8000 \
          sentiment-ai:${IMAGE_TAG}

        docker ps | grep sentiment-staging
        echo "Staging disponible sur http://localhost:8001/health"
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
            echo 'Pipeline echoue. Consultez les logs.'
        }
    }
}