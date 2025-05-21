pipeline {
    agent {
        docker {
            image 'jackzmc/spcomp:debian-1.12-git7202'
            reuseNode true
        }
    }

    stages {
        stage("Build Plugins") {
            steps {
                sh '/sourcemod/compile_jenkins.sh || echo fail && exit 0'
            }
            post {
                success {
                    dir("plugins") {
                        archiveArtifacts(artifacts: '*.smx', fingerprint: true)
                    }
                }
            }
        }
        
    }
}
