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



