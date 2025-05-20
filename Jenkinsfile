pipeline {
    agent {
        docker {
            image 'jackzmc/spcomp:alpine-1.12.0-git7169'
            reuseNode true
            args '-v ${PWD}:/build'
        }
    }

    stages {
        stage("Build Plugins") {
            sh "cd /build/scripting"
            sh "for file in *.sp; do spcomp -o ../plugins/$file.smx -i /sourcemod/include -i include; done"
        }
        post {
            success {
                archiveArtifacts(artifacts: 'plugins/*.smx', fingerprint: true)
            }
        }
    }
}
