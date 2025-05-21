pipeline {
    agent {
        docker {
<<<<<<< HEAD
            image 'jackzmc/spcomp:debian-1.12-git7202'
            reuseNode true
=======
            image 'jackzmc/spcomp:alpine-1.12.0-git7169'
            reuseNode true
            args '-v ${PWD}:/build'
>>>>>>> 4bc4b0e8fe05d3e4948d40d12aa0ee5a10212d47
        }
    }

    stages {
        stage("Build Plugins") {
            steps {
<<<<<<< HEAD
                sh '/sourcemod/compile_jenkins.sh || echo fail && exit 0'
            }
            post {
                success {
                    dir("plugins") {
                        archiveArtifacts(artifacts: '*.smx', fingerprint: true)
                    }
=======
                sh "cd /build/scripting"
                sh "for file in *.sp; do spcomp -o ../plugins/$file.smx -i /sourcemod/include -i include; done"
            }
            post {
                success {
                    archiveArtifacts(artifacts: 'plugins/*.smx', fingerprint: true)
>>>>>>> 4bc4b0e8fe05d3e4948d40d12aa0ee5a10212d47
                }
            }
        }
        
    }
<<<<<<< HEAD
}
=======
}
>>>>>>> 4bc4b0e8fe05d3e4948d40d12aa0ee5a10212d47
