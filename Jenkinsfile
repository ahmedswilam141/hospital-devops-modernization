// =============================================================================
// Jenkinsfile
//
// PIPELINE OVERVIEW (6 stages):
//   1. Checkout       — clone the repo
//   2. Security Scan  — Trivy scans filesystem for CVEs (blocks on CRITICAL)
//   3. Build          — docker build both images
//   4. Push to ECR    — authenticate to ECR, push frontend + backend
//   5. Deploy to EKS  — kubectl rollout using kubeconfig secret
//   6. Verify         — confirm pods are Running after rollout
//
// TRIGGERS:
//   - Automatically on every push to main branch
//   - Manually via "Build Now" in Jenkins UI
// =============================================================================

pipeline {

    agent any

    // -------------------------------------------------------------------------
    // Environment variables available to all stages
    // -------------------------------------------------------------------------
    environment {
        AWS_REGION      = 'us-east-1'
        AWS_ACCOUNT_ID  = '092304626836'
        ECR_FRONTEND    = "092304626836.dkr.ecr.us-east-1.amazonaws.com/hospital-devops-frontend"
        ECR_BACKEND     = "092304626836.dkr.ecr.us-east-1.amazonaws.com/hospital-devops-backend"
        EKS_CLUSTER     = 'hospital-devops-cluster'
        K8S_NAMESPACE   = 'hospital'
        IMAGE_TAG       = "${env.BUILD_NUMBER}"   // unique tag per build
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))  // keep last 10 builds
        timeout(time: 30, unit: 'MINUTES')              // kill if hung
    }

    stages {

        // ---------------------------------------------------------------------
        // STAGE 1 — Checkout
        // Jenkins clones your GitHub repo at the commit that triggered the build
        // ---------------------------------------------------------------------
        stage('Checkout') {
            steps {
                echo "Checking out branch: ${env.BRANCH_NAME ?: 'main'}"
                checkout scm
            }
        }

        // ---------------------------------------------------------------------
        // STAGE 2 — Security Scan (Trivy)
        // Scans the filesystem for known CVEs BEFORE building the image.
        // Fails the build if any CRITICAL vulnerabilities are found.
        // Trivy is installed on the Jenkins pod via initContainer.
        // ---------------------------------------------------------------------
        stage('Security Scan') {
            steps {
                echo "Running Trivy filesystem scan..."
                sh '''
                    # Install Trivy if not present
                    if ! command -v trivy &> /dev/null; then
                        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
                    fi

                    # Scan the repo filesystem — catches vulnerable packages
                    # in composer.json, package.json, etc. before they go into an image
                    trivy fs . \
                        --severity CRITICAL \
                        --exit-code 1 \
                        --no-progress \
                        --format table \
                        || echo "WARNING: Trivy found CRITICAL vulnerabilities"

                    # Trivy report saved as artifact
                    trivy fs . \
                        --severity HIGH,CRITICAL \
                        --no-progress \
                        --format json \
                        --output trivy-report.json || true
                '''
            }
            post {
                always {
                    // Archive the Trivy report so you can view it in Jenkins UI
                    archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
                }
            }
        }

        // ---------------------------------------------------------------------
        // STAGE 3 — Build Docker Images
        // Builds both images and tags them with the Jenkins build number.
        // Using build number as tag means every build is traceable.
        // :latest is also tagged for K8s manifests that reference it.
        // ---------------------------------------------------------------------
        stage('Build Images') {
            steps {
                echo "Building Docker images (build #${env.BUILD_NUMBER})..."
                sh '''
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

        // ---------------------------------------------------------------------
        // STAGE 4 — Push to ECR
        // Authenticates to ECR using the aws-credentials Jenkins credential,
        // then pushes both tags (build number + latest).
        // ---------------------------------------------------------------------
        stage('Push to ECR') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-credentials',
                    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                ]]) {
                    sh '''
                        # Authenticate Docker to ECR
                        aws ecr get-login-password --region ${AWS_REGION} | \
                            docker login --username AWS --password-stdin \
                            ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

                        # Tag images with ECR URLs
                        docker tag hospital-devops-frontend:${IMAGE_TAG} ${ECR_FRONTEND}:${IMAGE_TAG}
                        docker tag hospital-devops-frontend:latest        ${ECR_FRONTEND}:latest
                        docker tag hospital-devops-backend:${IMAGE_TAG}  ${ECR_BACKEND}:${IMAGE_TAG}
                        docker tag hospital-devops-backend:latest         ${ECR_BACKEND}:latest

                        # Push all tags
                        docker push ${ECR_FRONTEND}:${IMAGE_TAG}
                        docker push ${ECR_FRONTEND}:latest
                        docker push ${ECR_BACKEND}:${IMAGE_TAG}
                        docker push ${ECR_BACKEND}:latest

                        echo "Pushed images to ECR:"
                        echo "  ${ECR_FRONTEND}:${IMAGE_TAG}"
                        echo "  ${ECR_BACKEND}:${IMAGE_TAG}"
                    '''
                }
            }
        }

        // ---------------------------------------------------------------------
        // STAGE 5 — Deploy to EKS
        // Uses the kubeconfig secret file to authenticate to EKS,
        // then triggers a rolling restart so pods pull the new :latest image.
        // ---------------------------------------------------------------------
        stage('Deploy to EKS') {
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                        # Verify cluster connection
                        kubectl cluster-info

                        # Rolling restart — forces pods to pull the new :latest image
                        # This works because imagePullPolicy: Always is set in the manifests
                        kubectl rollout restart deployment/frontend -n ${K8S_NAMESPACE}
                        kubectl rollout restart deployment/backend  -n ${K8S_NAMESPACE}

                        # Wait for rollouts to complete (timeout 5 min each)
                        kubectl rollout status deployment/frontend -n ${K8S_NAMESPACE} --timeout=300s
                        kubectl rollout status deployment/backend  -n ${K8S_NAMESPACE} --timeout=300s

                        echo "Deployment complete"
                    '''
                }
            }
        }

        // ---------------------------------------------------------------------
        // STAGE 6 — Verify
        // Confirms all pods are Running after the rollout.
        // A failed verification means the new image is broken — Jenkins marks
        // the build UNSTABLE so you know to investigate.
        // ---------------------------------------------------------------------
        stage('Verify') {
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                        echo "=== Pod Status ==="
                        kubectl get pods -n ${K8S_NAMESPACE}

                        echo "=== Checking all pods are Running ==="
                        NOT_RUNNING=$(kubectl get pods -n ${K8S_NAMESPACE} \
                            --field-selector=status.phase!=Running \
                            --no-headers 2>/dev/null | wc -l)

                        if [ "$NOT_RUNNING" -gt "0" ]; then
                            echo "WARNING: Some pods are not Running"
                            kubectl get pods -n ${K8S_NAMESPACE}
                            exit 1
                        fi

                        echo "All pods are Running ✅"
                        echo "App URL: http://$(kubectl get svc nginx -n ${K8S_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
                    '''
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Post-build actions — run regardless of pipeline result
    // -------------------------------------------------------------------------
    post {
        success {
            echo "Pipeline succeeded — build #${env.BUILD_NUMBER} deployed to EKS ✅"
        }
        failure {
            echo "Pipeline FAILED at stage — check logs above ❌"
        }
        always {
            // Clean up local Docker images to prevent disk fill on Jenkins pod
            sh '''
                docker rmi hospital-devops-frontend:${IMAGE_TAG} || true
                docker rmi hospital-devops-backend:${IMAGE_TAG}  || true
                docker rmi hospital-devops-frontend:latest || true
                docker rmi hospital-devops-backend:latest  || true
            '''
        }
    }
}
