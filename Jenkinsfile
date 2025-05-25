pipeline {
    agent {
        docker {
            image 'jackzmc/spcomp:debian-1.12-git7202'
            reuseNode true
        }
    }

    stages {
        stage("Build Plugins") {
            agent {
                docker {
                    image 'jackzmc/spcomp:debian-1.12-git7202'
                    reuseNode true
                }
            }
            steps {
                sh '/sourcemod/compile_jenkins.sh'
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
