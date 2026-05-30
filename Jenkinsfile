pipeline {

    agent {
        kubernetes {
            yaml '''
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: jnlp
    image: jenkins/inbound-agent:latest
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
  - name: tools
    image: 092304626836.dkr.ecr.us-east-1.amazonaws.com/hospital-devops-jenkins-agent:latest
    imagePullPolicy: Always
    command:
    - sleep
    args:
    - infinity
    env:
    - name: DOCKER_HOST
      value: tcp://localhost:2375
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
  - name: dind
    image: docker:24-dind
    securityContext:
      privileged: true
    env:
    - name: DOCKER_TLS_CERTDIR
      value: ""
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 300m
        memory: 384Mi
'''
        }
    }

    environment {
        AWS_REGION      = 'us-east-1'
        AWS_ACCOUNT_ID  = '092304626836'
        ECR_FRONTEND    = "092304626836.dkr.ecr.us-east-1.amazonaws.com/hospital-devops-frontend"
        ECR_BACKEND     = "092304626836.dkr.ecr.us-east-1.amazonaws.com/hospital-devops-backend"
        EKS_CLUSTER     = 'hospital-devops-cluster'
        K8S_NAMESPACE   = 'hospital'
        IMAGE_TAG       = "${env.BUILD_NUMBER}"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
    }

    stages {

        stage('Checkout') {
            steps {
                echo "Checking out branch: ${env.BRANCH_NAME ?: 'master'}"
                checkout scm
            }
        }

        stage('Security Scan') {
            steps {
                container('tools') {
                    echo "Running Trivy filesystem scan..."
                    sh '''
                        trivy fs . \
                            --severity CRITICAL \
                            --exit-code 0 \
                            --no-progress \
                            --format table

                        trivy fs . \
                            --severity HIGH,CRITICAL \
                            --no-progress \
                            --format json \
                            --output trivy-report.json || true
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
                }
            }
        }

        stage('Build Images') {
            steps {
                container('tools') {
                    echo "Building Docker images (build #${env.BUILD_NUMBER})..."
                    sh '''
                        until docker info > /dev/null 2>&1; do
                            echo "Waiting for Docker daemon..."
                            sleep 2
                        done

                        docker build \
                            -t hospital-devops-frontend:${IMAGE_TAG} \
                            -t hospital-devops-frontend:latest \
                            -f docker/Dockerfile.frontend .

                        docker build \
                            -t hospital-devops-backend:${IMAGE_TAG} \
                            -t hospital-devops-backend:latest \
                            -f docker/Dockerfile.backend .

                        echo "Built images:"
                        docker images | grep hospital-devops
                    '''
                }
            }
        }

        stage('Push to ECR') {
            steps {
                container('tools') {
                    withCredentials([[
                        $class: 'AmazonWebServicesCredentialsBinding',
                        credentialsId: 'aws-credentials',
                        accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                        secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                    ]]) {
                        sh '''
                            aws ecr get-login-password --region ${AWS_REGION} | \
                                docker login --username AWS --password-stdin \
                                ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

                            docker tag hospital-devops-frontend:${IMAGE_TAG} ${ECR_FRONTEND}:${IMAGE_TAG}
                            docker tag hospital-devops-frontend:latest        ${ECR_FRONTEND}:latest
                            docker tag hospital-devops-backend:${IMAGE_TAG}  ${ECR_BACKEND}:${IMAGE_TAG}
                            docker tag hospital-devops-backend:latest         ${ECR_BACKEND}:latest

                            docker push ${ECR_FRONTEND}:${IMAGE_TAG}
                            docker push ${ECR_FRONTEND}:latest
                            docker push ${ECR_BACKEND}:${IMAGE_TAG}
                            docker push ${ECR_BACKEND}:latest

                            echo "Pushed to ECR: build #${IMAGE_TAG}"
                        '''
                    }
                }
            }
        }

        stage('Deploy to EKS') {
            steps {
                container('tools') {
                    withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                        sh '''
                            kubectl cluster-info
                            kubectl rollout restart deployment/frontend -n ${K8S_NAMESPACE}
                            kubectl rollout restart deployment/backend  -n ${K8S_NAMESPACE}
                            kubectl rollout status deployment/frontend  -n ${K8S_NAMESPACE} --timeout=300s
                            kubectl rollout status deployment/backend   -n ${K8S_NAMESPACE} --timeout=300s
                            echo "Deployment complete"
                        '''
                    }
                }
            }
        }

        stage('Verify') {
            steps {
                container('tools') {
                    withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                        sh '''
                            echo "=== Pod Status ==="
                            kubectl get pods -n ${K8S_NAMESPACE}

                            NOT_RUNNING=$(kubectl get pods -n ${K8S_NAMESPACE} \
                                --field-selector=status.phase!=Running \
                                --no-headers 2>/dev/null | wc -l)

                            if [ "$NOT_RUNNING" -gt "0" ]; then
                                echo "WARNING: Some pods are not Running"
                                kubectl get pods -n ${K8S_NAMESPACE}
                                exit 1
                            fi

                            echo "All pods Running ✅"
                            echo "App URL: http://$(kubectl get svc nginx -n ${K8S_NAMESPACE} \
                                -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Pipeline succeeded — build #${env.BUILD_NUMBER} deployed ✅"
        }
        failure {
            echo "Pipeline FAILED — check logs above ❌"
        }
        always {
            container('tools') {
                sh '''
                    docker rmi hospital-devops-frontend:${IMAGE_TAG} || true
                    docker rmi hospital-devops-backend:${IMAGE_TAG}  || true
                    docker rmi hospital-devops-frontend:latest || true
                    docker rmi hospital-devops-backend:latest  || true
                '''
            }
        }
    }
}
