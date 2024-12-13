# Entregable Terraform + SCV + Jenkins

## Instrucciones del despliegue 

Para crear y desplegar este proyecto vamos a seguir los siguientes pasos: 

Cabe destacar que debemos de tener descargado Docker y Terraform en nuestro dispositivo.

### Creamos la imagen de Jenkins

Para crear la imagen de Jenkins primero debemos de crear el archivo `Dockerfile` con la siguiente información:

```dockerfile
FROM jenkins/jenkins:2.479.2-jdk17
USER root
RUN apt-get update && apt-get install -y lsb-release
RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
https://download.docker.com/linux/debian/gpg
RUN echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
https://download.docker.com/linux/debian \
$(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
RUN apt-get update && apt-get install -y docker-ce-cli
USER jenkins
RUN jenkins-plugin-cli --plugins "blueocean docker-workflow token-macro json-path-api" 
``` 

Detalladamente este Dockerfile lo que hace es lo siguiente: 
Descarga e instala la imagen de Jetkins personalizada con Blue Ocean, habilita el acceso al cliente de Docker para que Jenkins pueda ejecutar los comandos de Docker desde sus pipelines, instala los plugins esenciales como Blue Ocean, docker-workflow,... para que los pipelines se puedan gestionar visualmente y se pueda trabajar con los contenedores Docker, y por ultimo garantiza la seguridad ejecutando Jenkins con su usuario estandar en vez de root.


Para aplicar la configuración debemos de ejecutar el comando :

`docker build -t myjenkins-blueocean . `

### Desplegamos los contenedores Docker con Terraform

Para desplegar los contenedores Docker con Terraform debemos de crear un archivo `main.tf` con la siguiente configuración:

```BASH   
terraform {
required_providers {
    docker = {
    source = "kreuzwerker/docker"
    version = "~> 3.0.1"
    }
}
}

provider "docker" {}

resource "docker_network" "jenkins" {
name = "jenkins"
}

resource "docker_volume" "jenkins_data" {
name = "jenkins-data"
}

resource "docker_volume" "jenkins_docker_certs" {
name = "jenkins-docker-certs"
}

resource "docker_container" "docker_in_docker" {
name    = "jenkins-docker"
image   = "docker:dind"
restart = "no"

privileged = true

networks_advanced {
    name = docker_network.jenkins.name
    aliases = ["docker"]
}

env = [
    "DOCKER_TLS_CERTDIR=/certs"
]

ports {
    internal = 2376
    external = 2376
}

volumes {
    volume_name    = docker_volume.jenkins_docker_certs.name
    container_path = "/certs/client"
}

volumes {
    volume_name    = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
}

command = ["--storage-driver", "overlay2"]
}

resource "docker_container" "jenkins" {
name    = "jenkins-blueocean"
image   = "myjenkins-blueocean"
restart = "on-failure"

networks_advanced {
    name = docker_network.jenkins.name
}

env = [
    "DOCKER_HOST=tcp://docker:2376",
    "DOCKER_CERT_PATH=/certs/client",
    "DOCKER_TLS_VERIFY=1"
]

ports {
    internal = 8080
    external = 8080
}

ports {
    internal = 50000
    external = 50000
}

volumes {
    volume_name    = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
}

volumes {
    volume_name    = docker_volume.jenkins_docker_certs.name
    container_path = "/certs/client"
    read_only      = true
}
}

```

Detalladamente, este archivo define recursos para la configuración de Jenkins usando Docker en Terraform. Este crea una red Docker llamada `jenkins` (la cual va a conectar los contendores), configura volúmenes Docker para almacenar datos de Jenkins y certificados TLS, define un contenedor Docker-in-Docker (docker:dind) para permitir que Jenkins ejecute Docker dentro de un contenedor, utilizando el puerto `2376` para la comunicación, y además, este contendor se configura con privilegios adicionales y monta los volúmenes necesarios.

El segundo contenedor que configura es Jenkins con Blue Ocean (myjenkins-blueocean), este se conecta a la red `jenkins` y utiliza los certificados TLS para comunicarse con Docker. En en `main.tf` también se exponen los puertos `8080` y `50000` para poder acceder a la interfaz web de Jenkins y a los agentes. Además este contenedor se reinicia automáticamente si falla y utiliza los volúmenes montados para almacenar los datos persistentes. Ambos contenedores están configurados para garantizar la seguridad y funcionalidadd del entorno. 


Para aplicar la configuración debemos de ejecutar primero el comando `terraform init`, para inicializar el proyecto Terraform y posteriormente,  el comando `terraform apply` para aplicar los archivos de configuración del directorio actual.


### Configuramos Jenkins

Para configurar Jenkins debemos de acceder a la URL de `http://localhost:8080` y nos pedirá que introduzcamos una contraseña para poder continuar con la instalación, para saber cuál es debemos de ejecutar el comando `docker logs jenkins-blueocean`, este nos devolverá información sobre el docker además de la contraseña que debemos de introducir. Una vez hecho esto debemos de seleccionar la instalación de pluggins que queramos. Ahora nos saldrá una pestaña donde debemos de introducir los datos correspondientes para crear el `first admin user` , como el nombre de usuario, la contraseña, el nombre completo y el correo electrónico. Posteriormente introducimos la misma URL que teniamos antes en el lugar correspondiente y ya tendríamos Jenkins configurado con nuestras credenciales.

Para crear un pipeline, primero seleccionamos crear `New Item` y la opción de pipeline. Ahora debemos de introducir el nombre que le queramos asignar y a continuación seleccionaremos `Pipeline script from SCM`, introducimos nuestro repositorio de Git, seleccionaremos la rama `main`, y el `Script Path` introducimos `docs/Jenkinsfile` y finalmente guardamos.

El archivo `Jenkinsfile` será el siguiente:

```groovy
pipeline {
    agent none
    options {
        skipStagesAfterUnstable()
    }
    stages {
        stage('Build') {
            agent {
                docker {
                    image 'python:3.12.0-alpine3.18'
                }
            }
            steps {
                sh 'python -m py_compile sources/add2vals.py sources/calc.py'
                stash(name: 'compiled-results', includes: 'sources/*.py*')
            }
        }
        stage('Test') {
            agent {
                docker {
                    image 'qnib/pytest'
                }
            }
            steps {
                sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py'
            }
            post {
                always {
                    junit 'test-reports/results.xml'
                }
            }
        }
        stage('Deliver') {
            agent any
            environment {
                VOLUME = '$(pwd)/sources:/src'
                IMAGE = 'cdrx/pyinstaller-linux:python2'
            }
            steps {
                dir(path: env.BUILD_ID) {
                    unstash(name: 'compiled-results')
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'pyinstaller -F add2vals.py'"
                }
            }
            post {
                success {
                    archiveArtifacts "${env.BUILD_ID}/sources/dist/add2vals"
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'rm -rf build dist'"
                }
            }
        }
    }
}
```

A continuación desplegamos el archivo `Jenkinsfile`, para ello debemos de pulsar el botón de `Build Now` y observaremos que mediante el pluggin de Blue Ocean, todo se ejecuta sin problemas pasando por cada una de las etapas correspondientes. Finalmente, para comprobar que todo se ha ejecutado correctamente, podemos pinchar en `Artifacts`  y podemos ver los archivos que se han generado durante la ejecución.




